import A2UISwiftUI
import BasicCatalogSwiftUI
import SwiftUI

/// 활성 surface 를 host 의 catalog (app · basic) 로 그린다. 없으면 EmptyView
public struct A2UISurfaceView: View {
    @ObservedObject var host: A2UISurfaceHost
    let surfaceID: String

    public init(host: A2UISurfaceHost, surfaceID: String) {
        self.host = host
        self.surfaceID = surfaceID
    }

    public var body: some View {
        if let vm = host.surface(surfaceID) {
            Surface(viewModel: vm, catalogs: host.catalogs)
        } else {
            EmptyView()
        }
    }
}
