//
//  AccessDatabase.swift
//  BeBrav
//
//  Created by Seonghun Kim on 28/01/2019.
//  Copyright © 2019 bumslap. All rights reserved.
//

import UIKit

class DatabaseHandler {
    
    // MARK:- Singleton
    static let shared = DatabaseHandler()
    
    // MARK:- Properties
    private let idField = "id"
    private let databaseName = "BeBravDatabase"
    private let databaseQueue = DispatchQueue(label: "DatabaseQueue", qos: .default)
    private var database: SQLiteDatabaseProtocol?
    
    public var fileManager: FileManagerProtocol = FileManager.default
    
    // MARK:- Open Database
    private func openDatabase() throws {
        database = try SQLiteDatabase.open(
            name: databaseName,
            fileManager: fileManager
        )
    }
    
    // MARK:- Check table is enable
    private func accessTable(data: DataModelProtocol) throws -> Bool {
        if database == nil {
            try openDatabase()
        }
        
        return database?.createTable(name: data.tableName, columns: data.columns) ?? false
    }
    
    // MARK:- Check access is enabled
    private func accessEnabled(data: DataModelProtocol) throws -> Bool {
        guard try self.accessTable(data: data) else {
            throw DatabaseError.accessTable
        }
        
        guard let list = try database?.fetch(
            table: data.tableName,
            column: idField,
            idField: idField,
            idRow: "\(data.id)",
            condition: nil
            ) else
        {
            throw DatabaseError.fetchData
        }
        
        return !list.isEmpty
    }
    
    // MARK:- Transfet data to model
    private func dataToModel(model: DataModelProtocol, data: [[String: String]])
        -> [DataModelProtocol]
    {
        return data.map{ model.setData(data: $0) }
    }
    
    // MARK:- Equal Model Filter
    private func equalFilter(model: DataModelProtocol, modelArray: [DataModelProtocol])
        -> [DataModelProtocol]
    {
        return modelArray.filter{ model.isEqual(model: $0) }
    }
    
    // MARK:- Fetch data from SQLite Database
    private func fetchData(type: DataType,
                           idField: String = "",
                           idRow: String = "",
                           condition: Condition? = .equal)
        throws -> [DataModelProtocol]
    {
        let model = type.model
        
        guard try self.accessTable(data: model) else {
            throw DatabaseError.accessTable
        }
        
        guard let dataArray = try self.database?.fetch(
            table: model.tableName,
            column: nil,
            idField: idField,
            idRow: idRow,
            condition: condition
            ) else
        {
            throw DatabaseError.fetchData
        }
        
        return dataToModel(model: model, data: dataArray).filter{ !$0.isEmpty }
    }
    
    // MARK:- Update data to SQLite Database
    private func updateData(data: DataModelProtocol) throws -> Bool {
        let id = data.id
        let table = data.tableName
        
        guard let dataArray = try self.database?.fetch(
            table: table,
            column: nil,
            idField: self.idField,
            idRow: id,
            condition: nil
            ) else
        {
            throw DatabaseError.fetchData
        }
        
        let modelList = self.dataToModel(model: data, data: dataArray)
        let modelArray = self.equalFilter(model: data, modelArray: modelList)
        
        if dataArray.count != modelArray.count || dataArray.count > 1 {
            try self.database?.delete(
                table: table,
                idField: self.idField,
                idRow: id
            )
        } else if modelArray.count == 1 {
            try data.variableList.forEach {
                try self.database?.update(
                    table: table,
                    column: $0.key,
                    row: $0.value,
                    idField: self.idField,
                    idRow: id
                )
            }
            return true
        }
        return false
    }
    
    // MARK:- Save new data or Update changed data to SQLite Database
    final func saveData(data: DataModelProtocol,
                        completion: @escaping (Bool, Error?) -> Void = {_,_ in })
    {
        databaseQueue.async {
            do {
                guard try self.accessTable(data: data) else {
                    completion(false, DatabaseError.accessTable)
                    return
                }
                
                if try self.updateData(data: data) {
                    completion(true, nil)
                    return
                }
                
                guard try self.database?.insert(
                    table: data.tableName,
                    columns: data.columns,
                    rows: data.rows
                    ) ?? false else
                {
                    completion(false, DatabaseError.saveData)
                    return
                }
                
                completion(true, nil)
            } catch let error {
                completion(false, error)
            }
        }
    }
    
    // MARK:- Delete Data to SQLite Database
    final func deleteData(data: DataModelProtocol,
                          completion: @escaping (Bool, Error?) -> Void = {_,_ in })
    {
        databaseQueue.async {
            do {
                guard try self.accessEnabled(data: data) else {
                    completion(false, DatabaseError.accessData)
                    return
                }
                
                try self.database?.delete(
                    table: data.tableName,
                    idField: self.idField,
                    idRow: String(data.id)
                )
                
                completion(true, nil)
            } catch let error {
                completion(false, error)
            }
        }
    }
    
    // MARK:- Read Data from SQLite Database
    final func readData(type: DataType,
                        id: String,
                        completion: @escaping (DataModelProtocol?, Error?) -> Void)
    {
        databaseQueue.async {
            do {
                let modelArray = try self.fetchData(
                    type: type,
                    idField: self.idField,
                    idRow: id
                )
                completion(modelArray.first, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Read Artist's Artwork Array
    final func readArtworkArray(artist: ArtistModel,
                                completion: @escaping ([ArtworkModel]?, Error?) -> Void)
    {
        databaseQueue.async {
            let type: DataType = .artworkData
            let idField = "userId"
            let idRow = artist.id
            
            do {
                guard let artworkArray = try self.fetchData(
                    type: type,
                    idField: idField,
                    idRow: idRow
                    ) as? [ArtworkModel]
                    else
                {
                    completion(nil, DatabaseError.fetchData)
                    return
                }
                
                completion(artworkArray, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Read Artwork Array with date
    final func readArtworkArray(keyDate: Double,
                                condition: Condition = .equal,
                                completion: @escaping ([ArtworkModel]?, Error?) -> Void)
    {
        databaseQueue.async {
            let type: DataType = .artworkData
            let idField = "date"
            let idRow = String(keyDate)
            
            do {
                guard let modelArray = try self.fetchData(
                    type: type,
                    idField: idField,
                    idRow: idRow,
                    condition: condition
                    ) as? [ArtworkModel]
                    else
                {
                    completion(nil, DatabaseError.fetchData)
                    return
                }
                completion(modelArray, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Read Artwork Array
    final func readArtworkArray(completion: @escaping ([ArtworkModel]?, Error?) -> Void)
    {
        databaseQueue.async {
            let type: DataType = .artworkData
            
            do {
                guard let modelArray = try self.fetchData(type: type) as? [ArtworkModel] else
                {
                    completion(nil, DatabaseError.fetchData)
                    return
                }
                completion(modelArray, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Data Type Enum
    enum DataType {
        case artistData
        case artworkData
        
        var model: DataModelProtocol {
            switch self {
            case .artistData:
                return ArtistModel()
            case .artworkData:
                return ArtworkModel()
            }
        }
    }
}
