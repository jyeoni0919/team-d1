//
//  URLSessionProtocol.swift
//  BeBrav
//
//  Created by bumslap on 25/01/2019.
//  Copyright © 2019 bumslap. All rights reserved.
//

import Foundation

protocol URLSessionProtocol {
    func dataTask(with request: URLRequest,
                  completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void)
        -> URLSessionDataTaskProtocol
}

extension URLSession: URLSessionProtocol {
    
    func dataTask(with request: URLRequest,
                  completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void)
        -> URLSessionDataTaskProtocol {
        let task = dataTask(with: request,
                            completionHandler: completionHandler) as URLSessionDataTask
        return task as URLSessionDataTaskProtocol
    }
}

extension URLSessionDataTask: URLSessionDataTaskProtocol {
    
}
