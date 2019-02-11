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
    private let database: SQLiteDatabaseProtocol?
    private let idField = "id"
    
    // MARk:- Initialize
    init(database: SQLiteDatabaseProtocol?) {
        self.database = database
    }
    
    convenience init() {
        let database: SQLiteDatabase?
        
        do {
            database = try SQLiteDatabase.open(
                name: databaseName,
                fileManager: FileManager.default
            )
        } catch let error {
            database = nil
            assertionFailure(error.localizedDescription)
        }
        
        self.init(database: database)
    }
    
    // MARK:- Check table is enable
    private func accessTable(type: DataType) throws -> Bool {
        let model = type.model
        let tableName = model.tableName
        
        guard let database = database else {
            throw DatabaseError.openDatabase(
                message: "No Database at DatabaseHandler"
            )
        }
        
        return database.createTable(name: tableName, columns: model.columns)
    }
    
    // MARK:- Check access is enabled
    private func accessEnabled(data: DataModelProtocol) throws -> Bool {
        let type: DataType = data is AuthorModel ? .AuthorData : .ArtworkData
        let table = data.tableName
        
        guard try self.accessTable(type: type) else {
            throw DatabaseError.accessTable(
                message: "Failure access to \(table) Table from \(#function) in \(#line)"
            )
        }
        
        guard let list = try database?.fetch(
            table: table,
            column: idField,
            idField: idField,
            idRow: "\(data.id)",
            condition: nil
            ) else
        {
                throw DatabaseError.fetch(
                    message: "Failure access to \(table) Table from \(#function) in \(#line)"
            )
        }
        
        return !list.isEmpty
    }
    
    // MARK:- Transfet data to model
    private func dataToModel(type: DataType, data: [[String: String]])
        -> [DataModelProtocol]
    {
        let modelArray: [DataModelProtocol] = data.map {
            switch type {
            case .AuthorData:
                let model = AuthorModel(data: $0)
                return model
            case .ArtworkData:
                let model = ArtworkModel(data: $0)
                return model
            }
        }
        
        return modelArray
    }
    
    // MARK:- Equal Model Filter
    private func equalFilter(type: DataType,
                             model: DataModelProtocol,
                             modelArray: [DataModelProtocol])
        -> [DataModelProtocol]
    {
        let modelArray = modelArray.filter { data in
            switch type {
            case .AuthorData:
                guard let data = data as? AuthorModel,
                    let model = model as? AuthorModel else { return false }
                return model == data
            case .ArtworkData:
                guard let data = data as? ArtworkModel,
                    let model = model as? ArtworkModel else { return false }
                return model == data
            }
        }
        
        return modelArray
    }
    
    // MARK:- Fetch Data from SQLite Database
    private func fetchData(type: DataType,
                           idField: String,
                           idRow: String,
                           condition: Condition = .equal)
        throws -> [DataModelProtocol]
    {
//        let model = type.model
        let table = type.model.tableName
        
        guard try self.accessTable(type: type) else {
            throw DatabaseError.accessTable(
                message: "Failure access to \(idRow) at \(type) from \(#function) in \(#line)"
            )
        }
        
        guard let dataArray = try self.database?.fetch(
            table: table,
            column: nil,
            idField: idField,
            idRow: idRow,
            condition: condition
            ) else
        {
            throw DatabaseError.fetch(
                message: "Failure fetch \(idRow) as \(table) from \(#function) in \(#line)"
            )
        }
        
        return dataToModel(type: type, data: dataArray).filter { !$0.isEmpty }
    }
    
    // MARK:- Update Data
    private func updateData(data: DataModelProtocol) throws -> Bool {
        let id = data.id
        let type: DataType = data is AuthorModel ? .AuthorData : .ArtworkData
        let table = data.tableName
        
        guard let dataArray = try self.database?.fetch(
            table: table,
            column: nil,
            idField: self.idField,
            idRow: id,
            condition: nil
            ) else
        {
            throw DatabaseError.fetch(
                message: "Failure fetch \(id) as \(table) from \(#function) in \(#line)"
            )
        }
        
        let modelList = self.dataToModel(
            type: type,
            data: dataArray
        )
        let modelArray = self.equalFilter(
            type: type,
            model: data,
            modelArray: modelList
        )
        
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
    
    // MARK:- Save new data or Update changed data
    public func saveData(data: DataModelProtocol,
                         completion: @escaping (Bool, Error?) -> Void = {_,_ in })
    {
        DispatchQueue.global(qos: .utility).async {
            let type: DataType = data is AuthorModel ? .AuthorData : .ArtworkData
            let table = data.tableName
            
            do {
                guard try self.accessTable(type: type) else {
                    completion(false, DatabaseError.accessTable(
                        message: "Failure access to \(table) from \(#function) in \(#line)"
                        )
                    )
                    return
                }
                
                if try !self.updateData(data: data) {
                    completion(true, nil)
                    return
                }
                
                guard try self.database?.insert(
                    table: table,
                    columns: data.columns,
                    rows: data.rows
                    ) ?? false else
                {
                    completion(false, DatabaseError.save(
                        message: "Failure save \(data) from \(#function) in \(#line)"
                        )
                    )
                    return
                }
                
                completion(true, nil)
            } catch let error {
                completion(false, error)
            }
        }
    }
    
    // MARK:- Delete Data
    public func deleteData(data: DataModelProtocol,
                           completion: @escaping (Bool, Error?) -> Void = {_,_ in })
    {
        DispatchQueue.global(qos: .userInitiated).async {
            let table = data.tableName
            
            do {
                guard try self.accessEnabled(data: data) else {
                    completion(false, DatabaseError.accessData(
                        message: "Failure access to \(data) from \(#function) in \(#line)"
                        )
                    )
                    return
                }
                
                try self.database?.delete(
                    table: table,
                    idField: self.idField,
                    idRow: String(data.id)
                )
                
                completion(true, nil)
            } catch let error {
                completion(false, error)
            }
        }
    }
    
    // MARK:- Read Data
    public func readData(type: DataType,
                         id: String,
                         completion: @escaping (DataModelProtocol?, Error?) -> Void)
    {
        DispatchQueue.global(qos: .userInitiated).async {
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
    
    // MARK:- Read Author's Artwork Array
    public func readArtworkArray(author: AuthorModel,
                                 completion: @escaping ([ArtworkModel]?, Error?) -> Void)
    {
        DispatchQueue.global(qos: .userInitiated).async {
            let type: DataType = .ArtworkData
            let idField = "authorId"
            let idRow = author.id
            
            do {
                guard let artworkArray = try self.fetchData(
                    type: type,
                    idField: idField,
                    idRow: idRow
                    ) as? [ArtworkModel]
                    else
                {
                    completion(nil, DatabaseError.fetch(
                        message: "Failure Trensfer DataModelArray to ArtworkModel from \(#function) in \(#line)")
                    )
                    return
                }
                
                completion(artworkArray, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Read Artwork Array with date
    public func readArtworkArray(keyDate: Double,
                                 condition: Condition = .equal,
                                 completion: @escaping ([DataModelProtocol]?, Error?) -> Void = {_,_ in })
    {
        DispatchQueue.global(qos: .userInitiated).async {
            let type: DataType = .ArtworkData
            let idField = "date"
            let idRow = String(keyDate)
            
            do {
                let modelArray = try self.fetchData(
                    type: type,
                    idField: idField,
                    idRow: idRow,
                    condition: condition
                )
                completion(modelArray, nil)
            } catch let error {
                completion(nil, error)
            }
        }
    }
    
    // MARK:- Data Type Enum
    enum DataType {
        case AuthorData
        case ArtworkData
        
        var model: DataModelProtocol {
            return self == .AuthorData ? AuthorModel() : ArtworkModel()
        }
    }
}

fileprivate let databaseName = "BeBravDatabase"

// MARK:- Database Error
fileprivate enum DatabaseError: Error {
    case openDatabase(message: String)
    case accessTable(message: String)
    case accessData(message: String)
    case save(message: String)
    case update(message: String)
    case fetch(message: String)
}

extension DatabaseError: CustomNSError {
    static var errorDomain: String = "SQLiteDatabase"
    var errorCode: Int {
        switch self {
        case .openDatabase:
            return 300
        case .accessTable:
            return 301
        case .accessData:
            return 302
        case .save:
            return 303
        case .update:
            return 304
        case .fetch:
            return 305
        }
    }
    
    var userInfo: [String : Any] {
        switch self {
        case let .openDatabase(code):
            return ["File": #file, "Type":"openDatabase", "Message":code]
        case let .accessTable(code):
            return ["File": #file, "Type":"accessTable", "Message":code]
        case let .accessData(code):
            return ["File": #file, "Type":"accessData", "Message":code]
        case let .save(code):
            return ["File": #file, "Type":"save", "Message":code]
        case let .update(code):
            return ["File": #file, "Type":"update", "Message":code]
        case let .fetch(code):
            return ["File": #file, "Type":"fetch", "Message":code]
        }
    }
}
