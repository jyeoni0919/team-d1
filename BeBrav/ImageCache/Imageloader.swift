//
//  ImageCacheProtocol.swift
//  BeBrav
//
//  Created by Seonghun Kim on 06/02/2019.
//  Copyright © 2019 bumslap. All rights reserved.
//

import Foundation

class ImageCacheProtocol {
    let cache = NSCache<AnyObject, AnyObject>()
    let fileManager: FileManagerProtocol
    let folderName = "ArtworkImage"
    
    init(fileManager: FileManagerProtocol) {
        self.fileManager = fileManager
    }
    
    convenience init() {
        self.init(fileManager: FileManager.default)
    }
}

extension ImageCacheProtocol: MemoryCacheProtocol {
    
}

extension ImageCacheProtocol: DiskCacheProtocol {

}
