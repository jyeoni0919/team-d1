//
//  paginatingCollectionView.swift
//  BeBrav
//
//  Created by bumslap on 05/02/2019.
//  Copyright © 2019 bumslap. All rights reserved.
//

import UIKit

private let reuseIdentifier = "Cell"

class PaginatingCollectionViewController: UICollectionViewController {
    
    //private var currentFilterType: String = ""
    
    private let imageLoader: ImageLoaderProtocol
    private let serverDatabase: FirebaseDatabaseService
    private let databaseHandler: DatabaseHandler
    init(serverDatabase: FirebaseDatabaseService, imageLoader: ImageLoaderProtocol, databaseHandler: DatabaseHandler) {
        self.databaseHandler = databaseHandler
        self.serverDatabase = serverDatabase
        self.imageLoader = imageLoader
        super.init(collectionViewLayout: MostViewedArtworkFlowLayout())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    ///checkIfValidPosition() 메서드가 적용된 이후 리턴되는 튜플을 구분하기 쉽게 적용한 type입니다.
    typealias CalculatedInformation = (sortedArray: [ArtworkDecodeType], index: Int)
    
    ///
    weak var pagingDelegate: PagingControlDelegate!
    
    ///메인뷰의 데이터를 전부 저장합니다
    private var artworkBucket: [ArtworkDecodeType] = []
    
    /// 데이터의 갯수가 batchSize보다 작아지면 다음번 요청은 제한하도록 해주는 프로퍼티입니다.
    private var isEndOfData = false
    
    ///batchSize만큼 데이터를 요청하게 되며 이 사이즈는 calculateNumberOfArtworksPerPage()
    ///메서드를 통해서 기기별 화면 크기에 맞는 한 페이지 분량의 데이터를 계산한 후 3을 뺸 크기입니다
    ///3을 빼주는 이유는 2x2크기의 레이아웃이 있기 때문이고 이 블록이 다른 블록의 4배의 공간을 차지하기
    ///때문입니다.
    private var batchSize = 0
    
    private let pageSize = 2
    
    private var itemsPerScreen = 0
    
    ///isLoading은 스크롤을 끝까지하여 데이터를 요청했을때 데이터가 전부 도착해야만 다음 스크롤때 해당
    ///메서드를 동작시킬수 있도록 제한하는 역할을 합니다
    private var isLoading = false
    
    /// recentTimestamp는 한번 정렬하여 얻어온 데이터를 이용해서 다음번 요청시 이 프로퍼티를 기준으로
    /// 다음 batchSize 만큼의 데이터를 다시 요청하기 위해 만든 프로퍼티입니다.
    private var recentTimestamp: Double!
    
    /// currentKey는 fetch한 데이터가 처음 요청하는 것인지 확인하기 위해서 구현한 프로퍼티입니다.
    private var currentKey: String!
    
    ///FooterView로 추가한 버튼을 관리하는 ReusableView 입니다.
    private var footerView: ArtworkAddFooterReusableView?
    ///
    private var latestContentsOffset: CGFloat = 0
    
    private let prefetchSize = 6
    
    
    ///네트워킹을 전체적으로 관리하는 인스탠스를 생성하기 위한 컨테이너 입니다.
    private let container = NetworkDependencyContainer()
    
    ///컨테이너로 만든 ServerDatabase 인스탠스입니다.
    private lazy var serverDB = container.buildServerDatabase()
    
    private lazy var serverST = container.buildServerStorage()
    private lazy var serverAu = container.buildServerAuth()
    private lazy var manager = ServerManager(authManager: serverAu,
                                             databaseManager: serverDB,
                                             storageManager: serverST,
                                             uid: "123")
    
    private var thumbImage: [String: UIImage] = [:]
    private var artworkImage: [String: UIImage] = [:]
    private var artworkDataFromDatabase: [ArtworkModel] = []
    
    //mainCollectionView 설정 관련 프로퍼티
    private let identifierFooter = "footer"
    private let spacing: CGFloat = 0
    private let insets: CGFloat = 2
    private let padding: CGFloat = 2
    private let columns: CGFloat = 3
    
    private let loadingIndicator: LoadingIndicatorView = {
        let indicator = LoadingIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.noticeLabel.text = "loadingImages".localized
        return indicator
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "BeBrav"
        if let layout = collectionView.collectionViewLayout as? MostViewedArtworkFlowLayout {
            itemsPerScreen = calculateNumberOfArtworksPerPage(numberOfColumns: CGFloat(columns), viewWidth: UIScreen.main.bounds.width, viewHeight: self.view.frame.height, spacing: padding, insets: padding)
                batchSize = itemsPerScreen * pageSize
            layout.numberOfItems = itemsPerScreen
            pagingDelegate = layout
        }
        setCollectionView()
        setLoadingView()
        fetchPages()
        
        if UIApplication.shared.keyWindow?.traitCollection.forceTouchCapability == .available
        {
            registerForPreviewing(with: self, sourceView: collectionView)
        }
    }
    
    func setCollectionView() {
        guard let collectionView = self.collectionView else { return }
        collectionView.alwaysBounceVertical = true
        collectionView.register(PaginatingCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = #colorLiteral(red: 0.1780431867, green: 0.1711916029, blue: 0.2278442085, alpha: 1)
        //collectionView.prefetchDataSource = self //TODO: 이미지로더 구현이후 적용
        collectionView.register(ArtworkAddFooterReusableView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: identifierFooter)
        
        //set filter right bar button
        let button = UIButton(type: UIButton.ButtonType.custom)
        button.setImage(#imageLiteral(resourceName: "filter (1)"), for: .normal)
        button.addTarget(self, action: #selector(filterButtonDidTap), for: .touchUpInside)
        
        let barButton = UIBarButtonItem(customView: button)
        barButton.customView?.translatesAutoresizingMaskIntoConstraints = false
        barButton.customView?.widthAnchor.constraint(equalToConstant: 20).isActive = true
        barButton.customView?.heightAnchor.constraint(equalToConstant: 20).isActive = true
        navigationItem.rightBarButtonItem = barButton
        
        if let layout = collectionView.collectionViewLayout as? MostViewedArtworkFlowLayout {
            layout.minimumInteritemSpacing = 0
            layout.sectionFootersPinToVisibleBounds = true
            layout.minimumLineSpacing = padding
            
        }
    }
    
    func setLoadingView() {
        collectionView.addSubview(loadingIndicator)
        loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        loadingIndicator.heightAnchor.constraint(equalToConstant: 60).isActive = true
        loadingIndicator.widthAnchor.constraint(equalToConstant: 200).isActive = true
        
//        loadingIndicator.deactivateIndicatorView()
        loadingIndicator.activateIndicatorView()
    }
    
    // MARK:- Return ArtworkViewController
    private func artworkViewController(index: IndexPath) -> ArtworkViewController {
        let imageLoader = ImageCacheFactory().buildImageLoader()
        let serverDatabase = NetworkDependencyContainer().buildServerDatabase()
        let databaseHandler = DatabaseHandler()
        let viewController = ArtworkViewController(imageLoader: imageLoader,
                                                   serverDatabase: serverDatabase,
                                                   databaseHandler: databaseHandler)
        
        guard let cell = collectionView.cellForItem(at: index) as? PaginatingCell else {
            return viewController
        }
        
        let artwork = artworkBucket[index.row]
        
        updateViewsCount(id: artwork.artworkUid)
        
        viewController.transitioningDelegate = self
        viewController.artwork = artwork
        viewController.artworkImage = cell.artworkImageView.image
        viewController.mainNavigationController = navigationController
        
        return viewController
    }
    
    private func updateViewsCount(id: String) {
        serverDatabase.read(
            path: "root/artworks/\(id)",
            type: ArtworkDecodeType.self,
            headers: ["X-Firebase-ETag": "true"],
            queries: nil
            )
        { (result, response) in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
            case .success(let data):
                guard let formedResponse = response as? HTTPURLResponse, let eTag = formedResponse.allHeaderFields["Etag"] as? String else { return }
                
                let encodeData = ArtworkDecodeType(
                    userUid: data.userUid,
                    authorName: data.authorName,
                    uid: data.artworkUid,
                    url: data.artworkUrl,
                    title: data.title,
                    timestamp: data.timestamp,
                    views: data.views + 1,
                    orientation: data.orientation,
                    color: data.color,
                    temperature: data.temperature
                )
                    
                self.serverDatabase.write(
                        path: "root/artworks/\(id)/",
                        data: encodeData,
                        method: .put,
                        headers: ["if-match": eTag]
                        )
                    { (result, response) in
                        switch result {
                        case .failure(let error):
                            print(error.localizedDescription)
                        case .success:
                            break
                        }
                    }
                }
            }
        }
    
    private func makeQueryAndRefresh(filterType: FilterType, isOn: Bool) {
        let orderBy: String?
        let queries: [URLQueryItem]?
        
        switch filterType {
        case .orientation:
            orderBy = "\"orientation\""
        case .color:
            orderBy = "\"color\""
        case .temperature:
            orderBy = "\"temperature\""
        case .none:
            orderBy = "\"timestamp\""
        }
        
        if filterType == .none {
            queries = [URLQueryItem(name: "orderBy", value: "\"timestamp\""),
                       URLQueryItem(name: "limitToLast", value: "\(self.batchSize)")
            ]
        }
        else {
            queries = [URLQueryItem(name: "orderBy", value: orderBy),
                       URLQueryItem(name: "orderBy", value: "\"timestamp\""),
                       URLQueryItem(name: "equalTo", value: "\(isOn)"),
                       URLQueryItem(name: "limitToLast", value: "\(batchSize)")]
        }
        
        if let queries = queries {
            refreshLayout(queries: queries, type: filterType, isOn: isOn)
        }
    }
    
    func makeAlert(title: String?) {
        var message: String?
        var trueActionTitle: String?
        var falseActionTitle: String?
        var filterType: FilterType?
        
        if title == "방향" {
            message = "어떤 방향의 작품을 보여드릴까요?"
            trueActionTitle = "가로 작품"
            falseActionTitle = "세로 작품"
            filterType = .orientation
        }
        else if title == "컬러" {
            message = "어떤 색의 작품을 보여드릴까요?"
            trueActionTitle = "컬러 작품"
            falseActionTitle = "흑백 작품"
            filterType = .color
        }
        else if title == "온도" {
            message = "어떤 온도의 작품을 보여드릴까요?"
            trueActionTitle = "차가운 작품"
            falseActionTitle = "따뜻한 작품"
            filterType = .temperature
        }
        
        guard let type = filterType else { return }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        
        let trueAction = UIAlertAction(title: trueActionTitle, style: .default, handler: { (action) in
            
            self.makeQueryAndRefresh(filterType: type, isOn: true)
        })
        
        let falseAction = UIAlertAction(title: falseActionTitle, style: .default, handler: { (action) in
            self.makeQueryAndRefresh(filterType: type, isOn: false)
        })
        
        let cancelAction = UIAlertAction(title: "취소", style: .cancel, handler: nil)
        
        alertController.addAction(trueAction)
        alertController.addAction(falseAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    @objc func filterButtonDidTap() {
        let alertController = UIAlertController(title: "filtering", message: "작품을 어떻게 필터링 할까요?", preferredStyle: .actionSheet)
        
        let orientationAction = UIAlertAction(title: "방향", style: .default) { (action) in
            self.makeAlert(title: action.title)
        }
        
        let colorAction = UIAlertAction(title: "컬러", style: .default) { (action) in
            self.makeAlert(title: action.title)
        }
        
        let temperatureAction = UIAlertAction(title: "온도", style: .default) { (action) in
            self.makeAlert(title: action.title)
        }
        
        let originAction = UIAlertAction(title: "모아보기", style: .default) { (action) in
            self.makeQueryAndRefresh(filterType: .none, isOn: true)
        }
        
        let cancelAction = UIAlertAction(title: "취소", style: .cancel, handler: nil)
        
        alertController.addAction(orientationAction)
        alertController.addAction(colorAction)
        alertController.addAction(temperatureAction)
        alertController.addAction(originAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
   
    @objc func userSettingButtonDidTap() {
        print(collectionView.indexPathsForVisibleItems)
        //TODO: setting 기능 추가
        UserDefaults.standard.removeObject(forKey: "uid")
        UserDefaults.standard.synchronize()
  
        
    }
    @objc func addArtworkButtonDidTap() {
        let flowLayout = UICollectionViewFlowLayout()
        let artAddCollectionViewController = ArtAddCollectionViewController(collectionViewLayout: flowLayout)
        artAddCollectionViewController.delegate = self
        present(artAddCollectionViewController, animated: true, completion: nil)
    }

    private func refreshLayout(queries: [URLQueryItem], type: FilterType, isOn: Bool) {
        guard let layout = collectionView.collectionViewLayout as? MostViewedArtworkFlowLayout else {
            return
        }
        layout.layoutRefresh()
        //layout.fetchPage = pageSize
        isEndOfData = false
        isLoading = false
        recentTimestamp = nil
        currentKey = nil
        artworkBucket.removeAll()
        thumbImage.removeAll()
        fetchPages(queries: queries, type: type, isOn: isOn)
    }
    
    // MARK: UICollectionViewDataSource
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return artworkBucket.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as? PaginatingCell else {
            return .init()
        }

        let artwork = artworkBucket[indexPath.row]
        
        if let image = artworkImage[artwork.artworkUid] {
            cell.artworkImageView.image = image
            artworkImage.removeValue(forKey: artwork.artworkUid)
        } else {
            fetchImage(artwork: artwork, indexPath: indexPath)
        }
        return cell
    }
    
    private func fetchImage(artwork: ArtworkDecodeType, indexPath: IndexPath?) {
        if artworkImage[artwork.artworkUid] == nil {
            guard let url = URL(string: artwork.artworkUrl) else { return }
            
            imageLoader.fetchImage(url: url, size: .small) { image, error in
                guard let image = image else { return }
                self.artworkImage[artwork.artworkUid] = image
                
                if let indexPath = indexPath {
                    DispatchQueue.main.async {
                        self.reloadCellImage(indexPath: indexPath)
                    }
                }
            }
            return
        }
        
        if let indexPath = indexPath {
            DispatchQueue.main.async {
                self.reloadCellImage(indexPath: indexPath)
            }
        }
    }

    
    private func reloadCellImage(indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? PaginatingCell else { return }
        guard collectionView.visibleCells.contains(cell) else { return }
        guard let image = artworkImage[artworkBucket[indexPath.item].artworkUid] else { return }
        
        cell.artworkImageView.image = image
    }
  
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let layout = collectionViewLayout as? MostViewedArtworkFlowLayout else {
            return
        }
        DispatchQueue.main.async {
            if self.traitCollection.verticalSizeClass == .compact {
                //self.refreshLayout()
                
            } else {
               // self.refreshLayout()

        }
      }
    }
}

extension PaginatingCollectionViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath)
        -> CGSize
    {
         let insetsNumber = columns + 1
         let width = (collectionView.frame.width - (insetsNumber * spacing) - (insetsNumber * insets)) / columns
         return CGSize(width: width, height: width)
     }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int)
        -> UIEdgeInsets
    {
        return UIEdgeInsets(top: insets, left: insets, bottom: insets, right: insets)
    }
    override func collectionView(_ collectionView: UICollectionView,
                                 didSelectItemAt indexPath: IndexPath)
    {
        let viewController = artworkViewController(index: indexPath)
        viewController.isAnimating = true
        
        present(viewController, animated: true) {
            viewController.isAnimating = false
        }
    }
}

extension PaginatingCollectionViewController {
    private func fetchPages(queries: [URLQueryItem], type: FilterType, isOn: Bool) {
        
        if !isEndOfData {
            isLoading = true
            loadingIndicator.activateIndicatorView()
            
            guard let layout = self.collectionViewLayout as? MostViewedArtworkFlowLayout else {
                return
            }
            if currentKey == nil {
                let queries = queries
                
                serverDB.read(path: "root/artworks",
                              type: [String: ArtworkDecodeType].self, headers: [:],
                              queries: queries) {
                                (result, response) in
                                switch result {
                                case .failure(let error):
                                    //TODO: 유저에게 보여줄 에러메세지 생성
                                    print(error)
                                case .success(let data):
                                    self.processData(data: data,
                                                     doNeedMore: false,
                                                     targetLayout: layout)
                                }
                }
            } else {
                //xcode버그 있어서 그대로 넣으면 가끔 빌드가 안됩니다.
                let timestamp = "\"timestamp\""
                let queries = [URLQueryItem(name: "orderBy", value: timestamp),
                               URLQueryItem(name: "endAt", value: "\(Int(recentTimestamp))"),
                               URLQueryItem(name: "limitToLast", value: "\(batchSize)")
                ]
                serverDB.read(path: "root/artworks",
                              type: [String: ArtworkDecodeType].self,
                              headers: [:],
                              queries: queries) {
                                (result, response) in
                                switch result {
                                case .failure(let error):
                                    //TODO: 유저에게 보여줄 에러메세지 생성
                                    print(error)
                                case .success(let data):
                                    self.processData(data: data,
                                                     doNeedMore: true,
                                                     targetLayout: layout)
                                    defer {
                                        DispatchQueue.main.async {
                                            self.loadingIndicator.deactivateIndicatorView()
                                            self.isLoading = false
                                        }
                                    }
                                }
                }
            }
        }
    }
    
    /// 컬렉션 뷰의 데이터를 페이지 단위로 받아오기 위한 메서드입니다.
    /// 이전에 데이터를 받아온 적이 있는지 currentKey를 통해서 확인합니다. 이후 쿼리를 생성하여 timestamp로
    /// 정렬된 데이터를 batchSize만큼 요청합니다. checkIfValidPosition()메서드를 이용하여 리턴된 값을
    /// 데이터 소스에 추가하고 nextLayoutYPosition을 Layout인스탠스의 pageNumber 프로퍼티에 전달해줍니다.
    func fetchPages() {
        
        if !isEndOfData {
            isLoading = true
//            loadingIndicator.activateIndicatorView()
            
            guard let layout = self.collectionViewLayout as? MostViewedArtworkFlowLayout else {
                return
            }
            if currentKey == nil {
                let queries = [URLQueryItem(name: "orderBy", value: "\"timestamp\""),
                               URLQueryItem(name: "limitToLast", value: "\(batchSize)")
                ]
                
                serverDB.read(path: "root/artworks",
                              type: [String: ArtworkDecodeType].self, headers: [:],
                              queries: queries) {
                                (result, response) in
                    switch result {
                    case .failure:
                        self.fetchDataFromDatabase(filter: .none, // TODO: 분류 필터 기능 추가후 수정
                                                   isOn: false, // TODO: 분류 필터 기능 추가후 수정
                                                   doNeedMore: false,
                                                   targetLayout: layout)
                    case .success(let data):
                        self.processData(data: data,
                                         doNeedMore: false,
                                         targetLayout: layout)
                    }
                    defer {
                        DispatchQueue.main.async {
                            self.loadingIndicator.deactivateIndicatorView()
                        }
                    }
                }
            } else {
                //xcode버그 있어서 그대로 넣으면 가끔 빌드가 안됩니다.
                let timestamp = "\"timestamp\""
                let queries = [URLQueryItem(name: "orderBy", value: timestamp),
                               URLQueryItem(name: "endAt", value: "\(Int(recentTimestamp))"),
                               URLQueryItem(name: "limitToLast", value: "\(batchSize)")
                ]
                serverDB.read(path: "root/artworks",
                              type: [String: ArtworkDecodeType].self,
                              headers: [:],
                              queries: queries) {
                                (result, response) in
                    switch result {
                    case .failure:
                        self.fetchDataFromDatabase(filter: .none, // TODO: 분류 필터 기능 추가후 수정
                                                   isOn: false, // TODO: 분류 필터 기능 추가후 수정
                                                   doNeedMore: false,
                                                   targetLayout: layout)
                    case .success(let data):
                        self.processData(data: data,
                                         doNeedMore: true,
                                         targetLayout: layout)
                    }
                    defer {
                        DispatchQueue.main.async {
                            
                            self.loadingIndicator.deactivateIndicatorView()
                        }
                    }
                }
            }
        }
    }
    
    private func fetchDataFromDatabase(filter: FilterType,
                                       isOn: Bool,
                                       doNeedMore: Bool,
                                       targetLayout: MostViewedArtworkFlowLayout)
    {
        if artworkDataFromDatabase.isEmpty {
            databaseHandler.readArtworkArray{ data, error in
                guard let data = data else { return }
                
                self.artworkDataFromDatabase = data.sorted{ $0.timestamp > $1.timestamp }
                
                self.processDataFromDatabase(filter: filter,
                                             isOn: isOn,
                                             doNeedMore: doNeedMore,
                                             targetLayout: targetLayout)
            }
        } else {
            processDataFromDatabase(filter: filter,
                                    isOn: isOn,
                                    doNeedMore: doNeedMore,
                                    targetLayout: targetLayout)
        }
    }
    
    private func processDataFromDatabase(filter: FilterType,
                                         isOn: Bool,
                                         doNeedMore: Bool,
                                         targetLayout: MostViewedArtworkFlowLayout)
    {
        var pageArtwork = artworkDataFromDatabase
        
        if let recentTimestamp = recentTimestamp {
            pageArtwork = artworkDataFromDatabase.filter{ $0.timestamp < recentTimestamp }
        }
        
        if filter != .none {
            switch filter {
            case .orientation:
                pageArtwork = pageArtwork.filter{ $0.orientation }
            case .color:
                pageArtwork = pageArtwork.filter{ $0.color }
            case .temperature:
                pageArtwork = pageArtwork.filter{ $0.temperature }
            case .none:
                break
            }
        }
        
        var artworksData: [String: ArtworkDecodeType] = [:]
        
        pageArtwork[0..<min(self.batchSize, pageArtwork.count)].forEach{
            artworksData[$0.id] = ArtworkDecodeType(artworkModel: $0)
        }
        
        self.processData(data: artworksData, doNeedMore: doNeedMore, targetLayout: targetLayout)
    }
    
    private func processData(data: [String: ArtworkDecodeType],
                             doNeedMore: Bool,
                             targetLayout: MostViewedArtworkFlowLayout) {
        
        let result = data.values.sorted()
        result.forEach{
            self.databaseHandler.saveData(data: ArtworkModel(artwork: $0))
            self.fetchImage(artwork: $0, indexPath: nil)
        }
        
        if doNeedMore {
            var indexList: [Int] = []
            
            self.currentKey = result.first?.artworkUid
            self.recentTimestamp = result.first?.timestamp
            
            if result.count < self.batchSize {
                self.isEndOfData = true
            }
            let infoBucket =  self.calculateCellInfo(fetchedData: result,
                                                     batchSize: self.itemsPerScreen)
            
            infoBucket.forEach {
                self.artworkBucket.append(contentsOf: $0.sortedArray)
                indexList.append($0.index)
            }
            
            DispatchQueue.main.async {
                self.pagingDelegate.constructNextLayout(indexList: indexList, pageSize: result.count)
                let indexPaths = self.calculateIndexPathsForReloading(from: result)
                self.collectionView.insertItems(at: indexPaths)
            }
            
        } else {
            self.currentKey = result.first?.artworkUid
            self.recentTimestamp = result.first?.timestamp
            
            if result.count < self.batchSize {
                self.isEndOfData = true
            }
            targetLayout.fetchPage = result.count
            let infoBucket =
                self.calculateCellInfo(fetchedData: result,
                                       batchSize: self.itemsPerScreen)
            infoBucket.forEach {
                self.artworkBucket.append(contentsOf: $0.sortedArray)
                targetLayout.prepareIndex.append($0.index)
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.collectionView.reloadData()
            }
        }
    }
    
    private func calculateIndexPathsForReloading(from newArtworks: [ArtworkDecodeType]) -> [IndexPath] {
        let startIndex = artworkBucket.count - newArtworks.count
        let endIndex = startIndex + newArtworks.count
        return (startIndex..<endIndex).map { IndexPath(row: $0, section: 0) }
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForFooterInSection section: Int) -> CGSize {
            return .init(width: view.frame.width, height: 60)
    }
    
    override func collectionView(_ collectionView: UICollectionView,
                                 viewForSupplementaryElementOfKind kind: String,
                                 at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionFooter:
                guard let footerView =
                    collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                    withReuseIdentifier: identifierFooter,
                                                                    for: indexPath) as? ArtworkAddFooterReusableView else {
                    return UICollectionReusableView.init()
                }
                footerView.addArtworkButton.addTarget(self,
                                                      action: #selector(addArtworkButtonDidTap),
                                                      for: .touchUpInside)
                self.footerView = footerView
                return footerView
        default:
        return UICollectionReusableView.init()
        }
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                           willDecelerate decelerate: Bool) {
        let currentOffset = scrollView.contentOffset.y
        let maxOffset = scrollView.contentSize.height - scrollView.frame.size.height
     
        if maxOffset - currentOffset <= 40{
            if !isEndOfData {
                self.loadingIndicator.activateIndicatorView()
            }
        }
    }
    
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        latestContentsOffset = scrollView.contentOffset.y;
        print(scrollView.contentOffset.y)
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y > 0 {
            if self.latestContentsOffset > scrollView.contentOffset.y {
                self.footerView?.addArtworkButton.alpha = 1
            }
            else if (self.latestContentsOffset < scrollView.contentOffset.y) {
                    self.footerView?.addArtworkButton.alpha = 0
            }
        }
    }
    
   private func calculateCellInfo(fetchedData: [ArtworkDecodeType],
                                  batchSize: Int)
    -> [CalculatedInformation]
   {
        var mutableDataBucket = fetchedData
        var calculatedInfoBucket: [CalculatedInformation] = []
        let numberOfPages = fetchedData.count / batchSize
        for _ in 0..<numberOfPages {
            
            var currentBucket: [ArtworkDecodeType] = []
            for _ in 0..<batchSize {
                currentBucket.append(mutableDataBucket.removeLast())
            }
            let calculatedInfo: CalculatedInformation =
                checkIfValidPosition(data: currentBucket,
                                     numberOfColumns: Int(columns))
            calculatedInfoBucket.append(calculatedInfo)
            currentBucket.removeAll()
        }
        
        if !mutableDataBucket.isEmpty {
            let calculatedInfo: CalculatedInformation =
                checkIfValidPosition(data: mutableDataBucket,
                                     numberOfColumns: Int(columns))
            calculatedInfoBucket.append(calculatedInfo)
        }
        return calculatedInfoBucket
    }
}

extension PaginatingCollectionViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath])
    {
        indexPaths.forEach {
            guard let url = URL(string: artworkBucket[$0.row].artworkUrl) else {
                return
            }//TODO: 이미지로더 구현이후 적용
            imageLoader.fetchImage(url: url, size: .small) { (image, error) in
                if error != nil {
                    assertionFailure("failed to make cell")
                    return
                }
            }
        }
    }
}

// MARK:- UIViewController Previewing Delegate
extension PaginatingCollectionViewController: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           viewControllerForLocation location: CGPoint)
        -> UIViewController?
    {
        guard let index = collectionView.indexPathForItem(at: location),
            let cell = collectionView.cellForItem(at: index) else {
                return .init()
        }
        previewingContext.sourceRect = cell.frame
        
        let viewController = artworkViewController(index: index)
        viewController.isPeeked = true
        
        return viewController
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           commit viewControllerToCommit: UIViewController)
    {
        guard let viewController = viewControllerToCommit as? ArtworkViewController else {
            return
        }
        viewController.isPeeked = false
        
        present(viewController, animated: false, completion: nil)
    }
}

// MARK:- PaginatingCollectionViewController Transitioning Delegate
extension PaginatingCollectionViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController)
        -> UIViewControllerAnimatedTransitioning?
    {
        guard let collectionView = collectionView,
            let index = collectionView.indexPathsForSelectedItems?.first,
            let cell = collectionView.cellForItem(at: index)
            else
        {
            return nil
        }
        
        let transition = CollectionViewControllerPresentAnimator()
        
        transition.viewFrame = view.frame
        transition.originFrame = collectionView.convert(cell.frame, to: nil)
        
        return transition
    }
    
    func animationController(forDismissed dismissed: UIViewController)
        -> UIViewControllerAnimatedTransitioning?
    {
        return nil
    }
}

extension PaginatingCollectionViewController: ArtAddCollectionViewControllerDelegate {
    func uploadArtwork(_ controller: ArtAddCollectionViewController, image: UIImage) {
        
        //FIXME: - SignIn 머지되면 수정
        manager.signIn(email: "t1@naver.com", password: "123456") { (result) in
            switch result {
            case .failure(let error):
                print(error)
                return
            case .success(let data):
                print("success")
                self.manager.uploadArtwork(image: image, scale: 0.1, path: "artworks", fileName: "test401", completion: { (result) in
                    switch result {
                    case .failure(let error):
                        print(error.localizedDescription)
                        return
                    case .success(let data):
                        break
                    }
                })
            }
        }
        
        DispatchQueue.main.async {
            self.fetchPages()
        }
    }
}

extension PaginatingCollectionViewController {
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        guard collectionView.visibleCells.contains(cell) else { return }
        
        let visubleCellsIndex = collectionView.visibleCells.map{collectionView.indexPath(for: $0)?.item ?? 0}
        let max = visubleCellsIndex.max{ $0 < $1 }
        
        guard let maxIndex = max, maxIndex != 0 else { return }
        var prefetchIndex = 0
        if maxIndex < indexPath.item {
            prefetchIndex = min(indexPath.item + prefetchSize, artworkBucket.count - 1)
            removePrefetchedArtwork(prefetchIndex: prefetchIndex, front: true)
        } else {
            prefetchIndex = min(indexPath.item - prefetchSize, artworkBucket.count - 1)
            removePrefetchedArtwork(prefetchIndex: prefetchIndex, front: false)
        }
        
        guard  artworkBucket.count > prefetchIndex, prefetchIndex >= 0 else { return }
        
        let artwork = artworkBucket[prefetchIndex]
        if artworkImage[artwork.artworkUid] == nil {
            self.fetchImage(artwork: artwork, indexPath: nil)
        }
    }
    

    private func removePrefetchedArtwork(prefetchIndex: Int, front: Bool) {
        if front {
            let targetIndex = prefetchIndex - prefetchSize
            
            guard targetIndex >= 0 else { return }
            
            for i in 0..<targetIndex {
                let artwork = artworkBucket[i]
                
                if artworkImage[artwork.artworkUid] != nil {
                    artworkImage.removeValue(forKey: artwork.artworkUid)
                }
            }
            
        } else {
            let targetIndex = prefetchIndex + prefetchSize
            
            guard targetIndex < artworkBucket.count else { return }
            
            for i in targetIndex..<artworkBucket.count {
                let artwork = artworkBucket[i]
                
                if artworkImage[artwork.artworkUid] != nil {
                    artworkImage.removeValue(forKey: artwork.artworkUid)
                }
            }

        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard artworkBucket.count - batchSize < indexPath.item else { return }
        
        if !isLoading {
            isLoading = true
            fetchPages()
        }
    }
}

fileprivate enum FilterType {
    case orientation
    case color
    case temperature
    case none
}
