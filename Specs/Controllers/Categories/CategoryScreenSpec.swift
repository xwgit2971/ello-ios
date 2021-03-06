////
///  CategoryScreenSpec.swift
//

@testable import Ello
import Quick
import Nimble


class CategoryScreenSpec: QuickSpec {
    class MockCategoryScreenDelegate: CategoryScreenDelegate {
        var selectedIndex: Int?
        var allCategoriesTappedCount = 0
        var gridListToggled = 0
        var searchButtonCount = 0
        var shareCount = 0
        var backCount = 0

        func categorySelected(index: Int) {
            selectedIndex = index
        }
        func allCategoriesTapped() {
            allCategoriesTappedCount += 1
        }
        func gridListToggled(sender: UIButton) {
            gridListToggled += 1
        }
        func searchButtonTapped() {
            searchButtonCount += 1
        }
        func shareTapped(sender: UIView) {
            shareCount += 1
        }
        func backTapped() {
            backCount += 1
        }
    }

    override func spec() {
        describe("CategoryScreen") {
            var subject: CategoryScreen!
            var delegate: MockCategoryScreenDelegate!
            var categoryInfo: [CategoryCardListView.CategoryInfo]!
            beforeEach {
                let infoA = CategoryCardListView.CategoryInfo(
                    title: "Art",
                    imageURL: URL(string: "https://example.com")
                    )
                let infoB = CategoryCardListView.CategoryInfo(
                    title: "Lorem ipsum dolor sit amet",
                    imageURL: URL(string: "https://example.com")
                    )
                subject = CategoryScreen()
                categoryInfo = [infoA, infoB, infoA, infoB]
                subject.set(categoriesInfo: categoryInfo, animated: false, completion: {})
                delegate = MockCategoryScreenDelegate()
                subject.delegate = delegate
            }

            describe("snapshots") {
                validateAllSnapshots(named: "CategoryScreen") {
                    return subject
                }
            }

            describe("CategoryScreenDelegate") {
                it("informs delegates of all categories selection") {
                    let categoryList: CategoryCardListView! = subview(of: subject, thatMatches: { $0 is CategoryCardListView })
                    let button: UIButton! = allSubviews(of: categoryList, thatMatch: { $0 is UIButton }).first
                    button.sendActions(for: .touchUpInside)
                    expect(delegate.allCategoriesTappedCount) == 1
                }
                it("informs delegates of category selection") {
                    let categoryList: CategoryCardListView! = subview(of: subject, thatMatches: { $0 is CategoryCardListView })
                    let button: UIButton! = allSubviews(of: categoryList, thatMatch: { $0 is UIButton }).last
                    button.sendActions(for: .touchUpInside)
                    expect(delegate.selectedIndex) == categoryInfo.count - 1
                }
            }
        }
    }
}
