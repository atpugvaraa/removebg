import SwiftUI
import Photos
import Kingfisher

class PHAssetImageDataProvider: ImageDataProvider {
    let asset: PHAsset
    let targetSize: CGSize
    
    init(asset: PHAsset, targetSize: CGSize) {
        self.asset = asset
        self.targetSize = targetSize
    }
    
    func data(handler: @escaping (Result<Data, Error>) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            if let image = image, let data = image.jpegData(compressionQuality: 0.9) {
                handler(.success(data))
            } else {
                handler(.failure(NSError(domain: "", code: -1, userInfo: nil)))
            }
        }
    }
    
    var cacheKey: String {
        return "\(asset.localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))"
    }
}

struct CustomPhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (UIImage) -> Void
    
    @StateObject private var viewModel = PhotoPickerViewModel()
    @State private var selectedAsset: PHAsset?
    @State private var showingPermissionDenied = false
    @State private var gridColumns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.permissionDenied {
                    PermissionDeniedView()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 1) {
                            ForEach(viewModel.assets, id: \.localIdentifier) { asset in
                                PhotoThumbnailView(asset: asset, isSelected: asset == selectedAsset)
                                    .aspectRatio(1, contentMode: .fill)
                                    .onTapGesture {
                                        selectedAsset = asset
                                    }
                            }
                        }
                        .padding(1)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Choose Photo")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let selectedAsset = selectedAsset {
                        Button("Choose") {
                            Task {
                                if let image = await viewModel.loadFullImage(from: selectedAsset) {
                                    onSelect(image)
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
        .task {
            await viewModel.requestAuthorization()
        }
    }
}

final class PhotoPickerViewModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var permissionDenied = false
    private let imageManager = PHCachingImageManager()
    
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        await MainActor.run {
            switch status {
            case .authorized, .limited:
                fetchAssets()
            case .denied, .restricted:
                permissionDenied = true
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
    
    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        let result = PHAsset.fetchAssets(with: options)
        assets = result.objects(at: IndexSet(0..<result.count))
    }
    
    func loadFullImage(from asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = true
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                continuation.resume(returning: image)
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let cellSize = CGSize(width: UIScreen.main.bounds.width/3 - 1, height: UIScreen.main.bounds.width/3 - 1)
        
        ZStack(alignment: .topTrailing) {
            KFImage.dataProvider(
                PHAssetImageDataProvider(
                    asset: asset,
                    targetSize: CGSize(
                        width: cellSize.width * UIScreen.main.scale,
                        height: cellSize.height * UIScreen.main.scale
                    )
                )
            )
            .placeholder {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .fade(duration: 0.25)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cellSize.width, height: cellSize.height)
            .clipped()
            .overlay(Color.black.opacity(isSelected ? 0.3 : 0))
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(.white)
            
            Text("Photo Access Required")
                .font(.title2)
                .foregroundStyle(.white)
            
            Text("Please enable photo access in Settings to use this feature.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    CustomPhotoPickerView { _ in }
}
