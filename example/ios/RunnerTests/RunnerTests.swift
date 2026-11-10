import Flutter
import UIKit
import XCTest

@testable import pick_photo

class RunnerTests: XCTestCase {

  func testPluginRegistration() {
    let plugin = PickPhotoPlugin()
    XCTAssertNotNil(plugin)
  }

}
