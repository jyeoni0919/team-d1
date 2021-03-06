//
//  PaginatingCell.swift
//  BeBrav
//
//  Created by bumslap on 05/02/2019.
//  Copyright © 2019 bumslap. All rights reserved.
//

import UIKit

class PaginatingCell: UICollectionViewCell {
    
    // MARK: UI
    let artworkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = nil
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = #colorLiteral(red: 0.968627451, green: 0.968627451, blue: 0.862745098, alpha: 1).withAlphaComponent(0.1) //TODO: 에셋으로 관리
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setLayout()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("error")
    }
    
    private func setLayout() {
        contentView.addSubview(artworkImageView)
        artworkImageView.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        artworkImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        artworkImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        artworkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        artworkImageView.image = nil
        
    }
    
}
