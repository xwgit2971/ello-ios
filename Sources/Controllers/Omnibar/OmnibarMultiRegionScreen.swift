//
//  OmnibarMultiRegionScreen.swift
//  Ello
//
//  Created by Colin Gray on 2/26/2015.
//  Copyright (c) 2015 Ello. All rights reserved.
//

import UIKit
import Photos
import MobileCoreServices
import FLAnimatedImage
import SVGKit
import PINRemoteImage


public enum OmnibarRegion {
    case Image(UIImage, NSData?, String?)
    case ImageURL(NSURL)
    case AttributedText(NSAttributedString)
    case Spacer
    case Error

    static func Text(str: String) -> OmnibarRegion {
        return AttributedText(ElloAttributedString.style(str))
    }
}


public class OmnibarMultiRegionScreen: UIView, OmnibarScreenProtocol {
    struct Size {
        static let margins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        static let textMargins = UIEdgeInsets(top: 22, left: 30, bottom: 9, right: 30)
        static let labelCorrection = CGFloat(8.5)
        static let innerTextMargin = CGFloat(11)
        static let bottomTextMargin = CGFloat(1)
        static let toolbarHeight = CGFloat(60)
        static let buttonHeight = CGFloat(45)
        static let buttonWidth = CGFloat(70)
    }

    class func canEditRegions(regions: [Regionable]?) -> Bool {
        if let regions = regions {
            return regions.all { region in
                return region is TextRegion || region is ImageRegion
            }
        }
        return false
    }

    var autoCompleteVC = AutoCompleteViewController()

// MARK: public access to text and image
    public var isEditing: Bool = false {
        didSet {
            submitButton.setTitle(NSLocalizedString("Update", comment: "Update button"), forState: .Normal)
        }
    }

    public var text: String?

    public var regions: [OmnibarRegion] {
        set {
            var regions = newValue
            if let last = regions.last where !last.isText {
                regions.append(.Text(""))
            }
            _regions = regions
            generateTableRegions()
            regionsTableView.reloadData()
        }
        get { return _regions }
    }
    public var _regions: [OmnibarRegion] = [.Text("")]
    public var tableViewRegions = [(Int?, OmnibarRegion)]()
    public var editableRegions = [(Int?, OmnibarRegion)]()

    public var currentTextPath: NSIndexPath?

    public var title: String = "" {
        didSet {
            navigationItem.title = title
        }
    }
    let navigationItem = UINavigationItem()

    public var avatarURL: NSURL? {
        willSet(newValue) {
            if avatarURL != newValue {
                if let avatarURL = newValue {
                    self.avatarButtonView.pin_setImageFromURL(avatarURL)                }
                else {
                    self.avatarButtonView.setImage(nil, forState: .Normal)
                }
            }
        }
    }

    public var avatarImage: UIImage? {
        willSet(newValue) {
            if avatarImage != newValue {
                if let avatarImage = newValue {
                    self.avatarButtonView.setImage(avatarImage, forState: .Normal)
                }
                else {
                    self.avatarButtonView.setImage(nil, forState: .Normal)
                }
            }
        }
    }

    public var canGoBack: Bool = false {
        didSet { setNeedsLayout() }
    }

    public var currentUser: User?

// MARK: internal and/or private vars

    weak public var delegate: OmnibarScreenDelegate?

    public let avatarButtonView = UIButton()

    let cancelButton = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    public let cameraButton = UIButton(frame: CGRect(x: 44, y: 0, width: 44, height: 44))
    let navigationBar = ElloNavigationBar(frame: CGRectZero)
    let submitButton = PostElloButton(frame: CGRect(x: 98, y: 0, width: 90, height: 44))
    let buttonContainer = UIView(frame: CGRect(x: 0, y: 0, width: 190, height: 60))
    let statusBarUnderlay = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 20))

    let regionsTableView = UITableView()
    let textScrollView = UIScrollView()
    let textContainer = UIView()
    public let textView: UITextView
    var autoCompleteContainer = UIView()
    var autoCompleteThrottle = debounce(0.4)
    var autoCompleteShowing = false
    private var currentImage: UIImage?

// MARK: init

    override public init(frame: CGRect) {
        _regions = [.Text("")]
        textView = OmnibarTextCell.generateTextView()
        super.init(frame: frame)

        backgroundColor = UIColor.whiteColor()
        autoCompleteContainer.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: 0)

        generateTableRegions()
        setupAutoComplete()
        setupAvatarView()
        setupImageSelectedViews()
        setupNavigationBar()
        setupToolbarButtons()
        setupTextViews()
        setupViewHierarchy()
        setupSwipeGesture()
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

// MARK: View setup code

    private func setupAutoComplete() {
        autoCompleteVC.view.frame = autoCompleteContainer.frame
        autoCompleteVC.delegate = self
        autoCompleteContainer.addSubview(autoCompleteVC.view)
    }

    // Avatar view (in the upper right corner) just needs to round its corners,
    // which is done in layoutSubviews.
    private func setupAvatarView() {
        avatarButtonView.backgroundColor = UIColor.blackColor()
        avatarButtonView.clipsToBounds = true
        avatarButtonView.addTarget(self, action: Selector("profileImageTapped"), forControlEvents: .TouchUpInside)
    }

    // This is the button, image, and icon that appear in lieu of the camera
    // button after an image is selected.  Tapping this button removes the
    // selected image.
    private func setupImageSelectedViews() {
    }
    private func setupNavigationBar() {
        let backItem = UIBarButtonItem.backChevronWithTarget(self, action: Selector("backAction"))
        navigationItem.leftBarButtonItem = backItem
        navigationItem.fixNavBarItemPadding()
        navigationBar.items = [navigationItem]

        statusBarUnderlay.frame.size.width = frame.width
        statusBarUnderlay.backgroundColor = .blackColor()
        statusBarUnderlay.autoresizingMask = .FlexibleWidth | .FlexibleBottomMargin
        addSubview(statusBarUnderlay)
    }

    // buttons that make up the "toolbar"
    private func setupToolbarButtons() {
        cameraButton.setSVGImages("camera")
        cameraButton.addTarget(self, action: Selector("addImageAction"), forControlEvents: .TouchUpInside)

        cancelButton.setSVGImages("x")
        cancelButton.addTarget(self, action: Selector("cancelEditingAction"), forControlEvents: .TouchUpInside)

        submitButton.addTarget(self, action: Selector("submitAction"), forControlEvents: .TouchUpInside)
        submitButton.setTitle(NSLocalizedString("Post", comment: "Post button"), forState: .Normal)
        submitButton.setTitleColor(UIColor.whiteColor(), forState: .Disabled)
        let image = SVGKImage(named: "arrow_white").UIImage!
        let imageView = UIImageView(image: image)
        imageView.center = CGPoint(x: submitButton.frame.width - image.size.width / 2 - 13, y: submitButton.frame.height / CGFloat(2))
        imageView.autoresizingMask = .FlexibleLeftMargin | .FlexibleTopMargin | .FlexibleBottomMargin
        submitButton.addSubview(imageView)
        submitButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: submitButton.frame.width - imageView.frame.minX - 2)
    }

    // The textContainer is the outer gray background.  The text view is
    // configured to fill that container (only the container and the text view
    // insets are modified in layoutSubviews)
    private func setupTextViews() {
        regionsTableView.dataSource = self
        regionsTableView.delegate = self
        regionsTableView.separatorStyle = .None
        regionsTableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: "OmnibarSpacerCell")
        regionsTableView.registerClass(OmnibarTextCell.self, forCellReuseIdentifier: OmnibarTextCell.reuseIdentifier())
        regionsTableView.registerClass(OmnibarImageCell.self, forCellReuseIdentifier: OmnibarImageCell.reuseIdentifier())
        regionsTableView.registerClass(OmnibarImageDownloadCell.self, forCellReuseIdentifier: OmnibarImageDownloadCell.reuseIdentifier())

        textScrollView.delegate = self
        let gesture = UITapGestureRecognizer(target: self, action: Selector("stopEditing"))
        textScrollView.addGestureRecognizer(gesture)
        textScrollView.clipsToBounds = true
        textContainer.backgroundColor = UIColor.greyE5()

        textView.clipsToBounds = false
        textView.editable = true
        textView.allowsEditingTextAttributes = true
        textView.selectable = true
        textView.delegate = self
        textView.autoresizingMask = .FlexibleHeight | .FlexibleWidth
        textView.autocorrectionType = .Yes
        textView.inputAccessoryView = autoCompleteContainer
    }

    private func setupViewHierarchy() {
        let views = [
            regionsTableView,
            textScrollView,
            navigationBar,
            avatarButtonView,
            buttonContainer,
        ]
        for view in views as [UIView] {
            self.addSubview(view)
        }
        for view in [cancelButton, cameraButton, submitButton] as [UIView] {
            buttonContainer.addSubview(view)
        }

        textScrollView.addSubview(textContainer)
        textScrollView.addSubview(textView)
        textScrollView.hidden = true
    }
    private func setupSwipeGesture() {
    }

// MARK: Generate regions

    private func generateTableRegions() {
        var tableViewRegions = [(Int?, OmnibarRegion)]()
        var prevWasImage = false
        for (index, region) in enumerate(_regions) {
            if region.isImage && prevWasImage {
                tableViewRegions.append((nil, .Spacer))
                prevWasImage = true
            }
            tableViewRegions.append((index, region))
            prevWasImage = region.isImage
        }
        self.tableViewRegions = tableViewRegions
        // NB: don't call `reloadData` here, because this method is called as part of
        // lots of table view updates
    }

// MARK: Public interface

    public func reportSuccess(title: String) {
        let alertController = AlertViewController(message: title)

        let cancelAction = AlertAction(title: NSLocalizedString("OK", comment: "ok button"), style: .Light, handler: .None)
        alertController.addAction(cancelAction)

        delegate?.omnibarPresentController(alertController)
        self.resetAfterSuccessfulPost()
    }

    private func resetAfterSuccessfulPost() {
        resetEditor()
    }

    public func profileImageTapped() {
        if let userParam = currentUser?.id {
            let profileVC = ProfileViewController(userParam: userParam)
            profileVC.currentUser = self.currentUser
            self.delegate?.omnibarPushController(profileVC)
        }
    }

    public func stopEditing() {
        textView.resignFirstResponder()
        textScrollView.hidden = true
        textScrollView.scrollsToTop = false
        regionsTableView.scrollsToTop = true
        currentTextPath = nil
    }

    public func startEditingAtPath(path: NSIndexPath) {
        textScrollView.hidden = false
        textScrollView.contentOffset = regionsTableView.contentOffset
        textScrollView.contentInset = regionsTableView.contentInset
        textScrollView.scrollIndicatorInsets = regionsTableView.scrollIndicatorInsets
        textScrollView.scrollsToTop = true
        regionsTableView.scrollsToTop = false
        updateEditingAtPath(path)
    }

    public func updateEditingAtPath(path: NSIndexPath, scrollPosition: UITableViewScrollPosition = .Middle) {
        var rect = regionsTableView.rectForRowAtIndexPath(path)
        textContainer.frame = OmnibarTextCell.boundsForTextContainer(rect)
        textScrollView.contentSize = regionsTableView.contentSize
        textView.frame = OmnibarTextCell.boundsForTextView(rect)
        textView.becomeFirstResponder()
    }

    public func startEditing() {
    }

    public func reportError(title: String, error: NSError) {
        let errorMessage = error.elloErrorMessage ?? error.localizedDescription
        reportError(title, errorMessage: errorMessage)
    }

    public func reportError(title: String, errorMessage: String) {
        let alertController = AlertViewController(message: title)

        let cancelAction = AlertAction(title: NSLocalizedString("OK", comment: "ok button"), style: .Light, handler: .None)
        alertController.addAction(cancelAction)

        delegate?.omnibarPresentController(alertController)
    }

// MARK: Keyboard events - animate layout update in conjunction with keyboard animation

    public func keyboardWillShow() {
        self.setNeedsLayout()
        UIView.animateWithDuration(Keyboard.shared().duration,
            delay: 0.0,
            options: Keyboard.shared().options,
            animations: {
                self.layoutIfNeeded()
            },
            completion: nil)
    }

    public func keyboardWillHide() {
        self.stopEditing()
        self.setNeedsLayout()
        UIView.animateWithDuration(Keyboard.shared().duration,
            delay: 0.0,
            options: Keyboard.shared().options,
            animations: {
                self.layoutIfNeeded()
            },
            completion: nil)
    }

    private func resignKeyboard() {
        textView.resignFirstResponder()
    }

// MARK: Layout and update views

    override public func layoutSubviews() {
        super.layoutSubviews()

        var screenTop = CGFloat(20)
        if canGoBack {
            UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: .Slide)
            navigationBar.frame = CGRect(x: 0, y: 0, width: self.frame.width, height: ElloNavigationBar.Size.height)
            screenTop += navigationBar.frame.height
            statusBarUnderlay.hidden = true
        }
        else {
            statusBarUnderlay.hidden = false
        }

        var avatarViewLeft = Size.margins.left
        avatarButtonView.frame = CGRect(x: avatarViewLeft, y: screenTop + Size.margins.top, width: Size.toolbarHeight, height: Size.toolbarHeight)
        avatarButtonView.layer.cornerRadius = Size.toolbarHeight / CGFloat(2)

        buttonContainer.frame = CGRect(x: frame.width - Size.margins.right, y: screenTop + Size.margins.top, width: 0, height: Size.toolbarHeight)
            .growLeft(buttonContainer.frame.width)
        for view in buttonContainer.subviews as! [UIView] {
            view.center.y = buttonContainer.frame.height / 2
        }

        regionsTableView.frame = CGRect(x: 0, y: buttonContainer.frame.maxY + Size.innerTextMargin, right: bounds.size.width, bottom: bounds.size.height)
        textScrollView.frame = regionsTableView.frame

        var bottomInset = Keyboard.shared().keyboardBottomInset(inView: self)
        if bottomInset == 0 {
            bottomInset = ElloTabBar.Size.height + Size.margins.bottom
        }
        else {
            bottomInset += Size.bottomTextMargin
        }

        regionsTableView.contentInset.bottom = bottomInset
        regionsTableView.scrollIndicatorInsets.bottom = bottomInset

        textScrollView.contentSize = regionsTableView.contentSize
        textScrollView.contentInset = regionsTableView.contentInset
        textScrollView.scrollIndicatorInsets = regionsTableView.scrollIndicatorInsets
    }

    private func resetEditor() {
        hideAutoComplete(textView)
        textView.resignFirstResponder()
        textView.text = ""
        updatePostState()
        _regions = [.Text("")]
        generateTableRegions()
        regionsTableView.reloadData()
    }

    public func updatePostState() {
        submitButton.enabled = canPost()
    }

// MARK: Button Actions

    func backAction() {
        delegate?.omnibarCancel()
    }

    public func startEditingAction() {
        startEditing()
    }

    public func cancelEditingAction() {
        if canPost() && !isEditing {
            let alertController = AlertViewController()

            let deleteAction = AlertAction(title: NSLocalizedString("Delete", comment: "Delete button"), style: ActionStyle.Dark, handler: { _ in
                self.resetEditor()
            })
            alertController.addAction(deleteAction)

            let cancelAction = AlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .Light, handler: .None)
            alertController.addAction(cancelAction)

            delegate?.omnibarPresentController(alertController)
        }
        else {
            delegate?.omnibarCancel()
        }
    }

    public func submitAction() {
        if canPost() {
            stopEditing()
            delegate?.omnibarSubmitted(_regions)
        }
    }

    public func swipedDown() {
        resignKeyboard()
    }

// MARK: Post logic

    public func canPost() -> Bool {
        for region in _regions {
            if !region.isEmpty {
                return true
            }
        }
        return false
    }

// MARK: Images

    // Notes on UITableView animations: since the modal is used here, the
    // animations only added complicated logic, no visual "bonus".  `reloadData`
    // is the way to go on this one.
    func userAddImage(image: UIImage?, data: NSData? = nil, type: String? = nil) {
        if let image = image {
            var prevCount = count(tableViewRegions)

            if let region = _regions.last where region.isEmpty {
                let lastIndex = count(_regions) - 1
                _regions.removeAtIndex(lastIndex)
                let lastIndexPath = NSIndexPath(forItem: count(tableViewRegions) - 1, inSection: 0)
                prevCount -= 1
            }

            _regions.append(.Image(image, data, type))
            _regions.append(.Text(""))
            generateTableRegions()
            let diffCount = count(tableViewRegions) - prevCount
            let paths = (1...diffCount).map { NSIndexPath(forItem: count(self.tableViewRegions) - $0, inSection: 0) }.reverse()
            regionsTableView.reloadData()
            regionsTableView.scrollToRowAtIndexPath(paths.last!, atScrollPosition: .None, animated: true)
        }

        updatePostState()
    }

    func userSetCurrentImageURL(imageURL: NSURL) {
        PINRemoteImageManager.sharedImageManager().downloadImageWithURL(imageURL) { result in
            if let image = result.image {
                self.userAddImage(image)
            }
        }
    }

// MARK: Camera / Image Picker

    public func addImageAction() {
        let alert = UIImagePickerController.alertControllerForImagePicker(openImagePicker)
        alert.map { self.delegate?.omnibarPresentController($0) }
    }

    private func isGif(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Bool {
        if length >= 4 {
            let isG = Int(buffer[0]) == 71
            let isI = Int(buffer[1]) == 73
            let isF = Int(buffer[2]) == 70
            let is8 = Int(buffer[3]) == 56

            return isG && isI && isF && is8
        }
        else {
            return false
        }
    }


// MARK: Text View editing

    // Updates the text view, including the overlay
    // and first responder state.  This method is meant to be used during
    // initialization.
    private func userSetCurrentText(value: NSAttributedString?) {
        textView.resignFirstResponder()
    }

}

extension OmnibarMultiRegionScreen: UITableViewDelegate, UITableViewDataSource {
    public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableViewRegions.count
    }

    public func tableView(tableView: UITableView, heightForRowAtIndexPath path: NSIndexPath) -> CGFloat {
        if let (_, region) = tableViewRegions.safeValue(path.row) {
            switch region {
            case let .AttributedText(attrdString):
                return OmnibarTextCell.heightForText(attrdString, tableWidth: regionsTableView.frame.width)
            case let .Image(image, _, _):
                return OmnibarImageCell.heightForImage(image, tableWidth: regionsTableView.frame.width)
            case let .ImageURL(url):
                return OmnibarImageDownloadCell.Size.height
            case let .Spacer:
                return OmnibarImageCell.Size.bottomMargin
            case .Error:
                return 0
            }
        }
        return 0
    }

    public func tableView(tableView: UITableView, cellForRowAtIndexPath path: NSIndexPath) -> UITableViewCell {
        if let (_, region) = tableViewRegions.safeValue(path.row) {
            let cell: UITableViewCell = tableView.dequeueReusableCellWithIdentifier(region.reuseIdentifier, forIndexPath: path) as! UITableViewCell
            cell.selectionStyle = .None

            switch region {
            case let .AttributedText(attributedText):
                let textCell = cell as! OmnibarTextCell
                textCell.attributedText = attributedText
            case let .Image(image, _, _):
                let imageCell = cell as! OmnibarImageCell
                imageCell.omnibarImage = image
            default: break
            }
            return cell
        }
        return UITableViewCell()
    }

    public func tableView(tableView: UITableView, didSelectRowAtIndexPath path: NSIndexPath) {
        if let (_, region) = tableViewRegions.safeValue(path.row) {
            switch region {
            case let .AttributedText(attributedText):
                startEditingAtPath(path)
                textView.attributedText = attributedText
                currentTextPath = path
            default:
                stopEditing()
            }
        }
    }

    public func tableView(tableView: UITableView, canEditRowAtIndexPath path: NSIndexPath) -> Bool {
        if let (_, region) = tableViewRegions.safeValue(path.row) {
            return region.deletable
        }
        return false
    }

    public func tableView(tableView: UITableView, commitEditingStyle style: UITableViewCellEditingStyle, forRowAtIndexPath path: NSIndexPath) {
        if style == .Delete {
            deleteImageAtIndexPath(path)
        }
    }

    public func deleteImageAtIndexPath(path: NSIndexPath) {
        if let (index_, region) = tableViewRegions.safeValue(path.row),
            index = index_ where region.deletable
        {
            if count(tableViewRegions) == 1 {
                _regions = [.Text("")]
                generateTableRegions()
                regionsTableView.reloadRowsAtIndexPaths([path], withRowAnimation: .Automatic)
            }
            else if let regionAbove = _regions.safeValue(index - 1),
                regionBelow = _regions.safeValue(index + 1)
            where regionAbove.isText && regionBelow.isText
            {
                let newText = NSMutableAttributedString()
                newText.appendAttributedString(regionAbove.text)
                if count(regionBelow.text.string.trim()) > 0 {
                    newText.appendAttributedString(ElloAttributedString.style("\n\n"))
                    newText.appendAttributedString(regionBelow.text)
                }

                _regions.removeAtIndex(index + 1)
                _regions.removeAtIndex(index)
                _regions[index - 1] = .AttributedText(newText)

                regionsTableView.beginUpdates()
                generateTableRegions()
                regionsTableView.reloadRowsAtIndexPaths([NSIndexPath(forItem: path.row - 1, inSection: 0)], withRowAnimation: .None)
                regionsTableView.deleteRowsAtIndexPaths([
                    path,
                    NSIndexPath(forItem: path.row + 1, inSection: 0),
                ], withRowAnimation: .Automatic)
                regionsTableView.endUpdates()
            }
            else if let regionAbove = _regions.safeValue(index - 1),
                regionBelow = _regions.safeValue(index + 1)
            where regionAbove.isImage && regionBelow.isImage
            {
                _regions.removeAtIndex(index)
                generateTableRegions()
                regionsTableView.reloadData()
            }
            else {
                _regions.removeAtIndex(index)
                var paths = [path]

                // remove the spacer *after* the deleted row (if it's the first
                // or N-1th row in series of image rows), and *before* the last
                // row (if it's the last row in a series of image rows)
                if let (_, region) = tableViewRegions.safeValue(path.row + 1) where region.isSpacer {
                    paths.append(NSIndexPath(forItem: path.row + 1, inSection: 0))
                }
                else if let (_, region) = tableViewRegions.safeValue(path.row - 1) where region.isSpacer {
                    paths.append(NSIndexPath(forItem: path.row - 1, inSection: 0))
                }

                regionsTableView.beginUpdates()
                if let last = _regions.last where !last.isText {
                    let insertPath = NSIndexPath(forItem: count(_regions), inSection: 0)
                    _regions.append(.Text(""))
                    regionsTableView.insertRowsAtIndexPaths([insertPath], withRowAnimation: .Automatic)
                }
                generateTableRegions()
                regionsTableView.deleteRowsAtIndexPaths(paths, withRowAnimation: .Automatic)
                regionsTableView.endUpdates()
            }
        }
        updatePostState()
    }

    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        textScrollView.contentSize = regionsTableView.contentSize
        if scrollView == regionsTableView {
        }
    }

    public func scrollViewDidScroll(scrollView: UIScrollView) {
        if scrollView == regionsTableView {
        }
        else {
            regionsTableView.contentOffset = scrollView.contentOffset
        }
    }

}


// MARK: UITextViewDelegate
extension OmnibarMultiRegionScreen: UITextViewDelegate {
    public func textViewShouldBeginEditing(textView: UITextView) -> Bool {
        return true
    }

    private func throttleAutoComplete(textView: UITextView, range: NSRange) {
        self.autoCompleteThrottle { [unowned self] in
            let autoComplete = AutoComplete()
            // deleting characters yields a range.length > 0, go back 1 character for deletes
            let location = range.length > 0 && range.location > 0 ? range.location - 1 : range.location
            if let match = autoComplete.check(textView.text, location: location) {
                self.autoCompleteVC.load(match) { count in
                    if count > 0 {
                        self.showAutoComplete(textView, count: count)
                    }
                    else if count == 0 {
                        self.hideAutoComplete(textView)
                    }
                }
            } else {
                self.hideAutoComplete(textView)
            }
        }
    }

    public func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText: String) -> Bool {
        if autoCompleteShowing && emojiKeyboardShowing() {
            return false
        }

        throttleAutoComplete(textView, range: range)
        nextTick { self.textViewDidChange(textView) }
        return true
    }

    public func textViewDidChange(textView: UITextView) {
        if let path = currentTextPath, cell = regionsTableView.cellForRowAtIndexPath(path) {
            let currentText = textView.attributedText
            let newRegion: OmnibarRegion = .AttributedText(currentText)
            let (index, _) = tableViewRegions[path.row]
            if let index = index {
                _regions[index] = newRegion
                tableViewRegions[path.row] = (index, newRegion)

                regionsTableView.reloadData()
                updateEditingAtPath(path, scrollPosition: .Bottom)
            }
        }
        updatePostState()
    }

    private func emojiKeyboardShowing() -> Bool {
        return textView.textInputMode?.primaryLanguage == nil || textView.textInputMode?.primaryLanguage == "emoji"
    }

    private func hideAutoComplete(textView: UITextView) {
        if autoCompleteShowing {
            autoCompleteShowing = false
            textView.autocorrectionType = .Yes
            textView.inputAccessoryView = nil
            textView.resignFirstResponder()
            textView.becomeFirstResponder()
        }
    }

    private func showAutoComplete(textView: UITextView, count: Int) {
        if !autoCompleteShowing {
            autoCompleteShowing = true
            textView.inputAccessoryView = autoCompleteContainer
            textView.autocorrectionType = .No
            textView.resignFirstResponder()
            textView.becomeFirstResponder()
        }

        let height: CGFloat = count > 3 ? AutoCompleteCell.cellHeight() * 3 : AutoCompleteCell.cellHeight() * CGFloat(count)
        if let constraint = textView.inputAccessoryView?.constraints().first as? NSLayoutConstraint {
            constraint.constant = height
        }
        autoCompleteContainer.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: height)
        autoCompleteVC.view.frame = autoCompleteContainer.frame
    }
}


extension OmnibarMultiRegionScreen: AutoCompleteDelegate {
    public func itemSelected(item: AutoCompleteItem) {
        if let name = item.result.name {
            let prefix = item.type == .Username ? "@" : ":"
            let newText = textView.text.stringByReplacingCharactersInRange(item.match.range, withString: prefix + name + " ")
            let currentText = ElloAttributedString.style(newText)
            textView.attributedText = currentText
            updatePostState()
            hideAutoComplete(textView)
        }
    }
}


// MARK: UIImagePickerControllerDelegate
extension OmnibarMultiRegionScreen: UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    private func openImagePicker(imageController: UIImagePickerController) {
        imageController.delegate = self
        delegate?.omnibarPresentController(imageController)
    }

    public func imagePickerController(controller: UIImagePickerController, didFinishPickingMediaWithInfo info: [NSObject: AnyObject]) {
        let library = PHPhotoLibrary.sharedPhotoLibrary()
        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage
        {
            if let url = info[UIImagePickerControllerReferenceURL] as? NSURL,
               let asset = PHAsset.fetchAssetsWithALAssetURLs([url], options: nil).firstObject as? PHAsset
            {
                    PHImageManager.defaultManager().requestImageDataForAsset(asset, options: nil) { imageData, dataUTI, orientation, info in
                        var buffer = UnsafeMutablePointer<UInt8>.alloc(imageData.length)
                        imageData.getBytes(buffer, length: imageData.length)
                        if self.isGif(buffer, length: imageData.length) {
                            self.userAddImage(image, data: imageData, type: "image/gif")
                        }
                        else {
                            self.userAddImage(image)
                        }
                        buffer.dealloc(imageData.length)
                        self.delegate?.omnibarDismissController(controller)
                    }
            }
            else {
                image.copyWithCorrectOrientationAndSize() { image in
                    self.userAddImage(image)
                    self.delegate?.omnibarDismissController(controller)
                }
            }
        }
        else {
            delegate?.omnibarDismissController(controller)
        }
    }

    public func imagePickerControllerDidCancel(controller: UIImagePickerController) {
        delegate?.omnibarDismissController(controller)
    }
}


extension OmnibarRegion {
    var deletable: Bool {
        switch self {
        case .Image: return true
        case let .AttributedText(text): return count(text.string) > 0
        default: return false
        }
    }

    var text: NSAttributedString {
        switch self {
        case let .AttributedText(text): return text
        default: return ElloAttributedString.style("")
        }
    }

    var isText: Bool {
        switch self {
        case .AttributedText: return true
        default: return false
        }
    }

    var isImage: Bool {
        switch self {
        case .Image: return true
        default: return false
        }
    }

    var isEmpty: Bool {
        switch self {
        case let .AttributedText(text): return count(text.string) == 0
        case .Spacer: return true
        default: return false
        }
    }

    var isSpacer: Bool {
        switch self {
        case .Spacer: return true
        default: return false
        }
    }

    var reuseIdentifier: String {
        switch self {
        case .Image: return OmnibarImageCell.reuseIdentifier()
        case .ImageURL: return OmnibarImageDownloadCell.reuseIdentifier()
        case .AttributedText: return OmnibarTextCell.reuseIdentifier()
        case .Spacer: return "OmnibarSpacerCell"
        case .Error: return ""
        }
    }
}

extension OmnibarRegion {
    var rawRegion: NSObject? {
        switch self {
        case let .Image(image, _, _): return image
        case let .AttributedText(text): return text
        default: return nil
        }
    }
}

extension OmnibarRegion: Printable, DebugPrintable {
    public var description: String {
        switch self {
        case let .Image(image, _, _): return "Image(size: \(image.size))"
        case let .ImageURL(url): return "ImageURL(url: \(url))"
        case let .AttributedText(text): return "AttributedText(text: \(text.string))"
        case let .AttributedText(text): return "AttributedText(text: \(text.string))"
        case .Spacer: return "Spacer()"
        case .Error: return "Error()"
        }
    }
    public var debugDescription: String {
        switch self {
        case let .Image(image, _, _): return "Image(size: \(image.size))"
        case let .ImageURL(url): return "ImageURL(url: \(url))"
        case let .AttributedText(text): return "AttributedText(text: \(text.string))"
        case .Spacer: return "Spacer()"
        case .Error: return "Error()"
        }
    }

}
