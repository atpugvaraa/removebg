//
//  BackgroundRemovalManager.swift
//  removebg
//
//  Created by Aarav Gupta on 18/01/25.
//

import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import Vision
import Kingfisher

@Observable
class BGRemovalManager {
    var isLoading: Bool = false
    var processedImage: UIImage?
    var originalImage: UIImage?
    var isProcessing: Bool = false
    var hasRemovedBackground: Bool = false
    
    var selectedItem: PhotosPickerItem? {
        didSet {
            if selectedItem != oldValue {
                processedImage = nil
                originalImage = nil
                hasRemovedBackground = false
                loadSelectedImage()
            }
        }
    }
    
    private var processingImageQueue = DispatchQueue(label: "Processing Image Queue", qos: .userInitiated)
    private var imageLoadingTask: Task<Void, Never>?
    
    var selectedPickerItemBinding: Binding<PhotosPickerItem?> {
        Binding {
            return self.selectedItem
        } set: { newValue in
            self.selectedItem = newValue
        }
    }
    
    func loadSelectedImage() {
        imageLoadingTask?.cancel()
        guard let selectedItem = selectedItem else { return }
        imageLoadingTask = Task {
            isLoading = true
            defer { isLoading = false }
            if let data = try? await selectedItem.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.originalImage = uiImage
                    self.processedImage = uiImage
                    self.hasRemovedBackground = false
                }
            } else {
                DispatchQueue.main.async {
                    self.originalImage = nil
                    self.processedImage = nil
                    self.hasRemovedBackground = false
                }
            }
        }
    }
    
    func createSticker() {
        guard let image = processedImage,
              !isProcessing,
              !hasRemovedBackground else { return }
        
        isProcessing = true
        guard let inputImage = CIImage(image: image) else {
            isProcessing = false
            return
        }
        
        processingImageQueue.async {
            guard let maskImage = self.createMaskImage(from: inputImage) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            
            let outputImage = self.apply(mask: maskImage, to: inputImage)
            let processedImage = self.render(ciImage: outputImage)
            
            DispatchQueue.main.async {
                self.processedImage = processedImage
                self.hasRemovedBackground = true
                self.isProcessing = false
            }
        }
    }
    
    func saveImageToPhotos() {
        guard let processedImage = processedImage, hasRemovedBackground else { return }
        
        // Create a new image with a fully transparent background
        let format = UIGraphicsImageRendererFormat()
        format.scale = processedImage.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: processedImage.size, format: format)
        let finalImage = renderer.image { context in
            // Fill with clear color first
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: processedImage.size))
            
            // Draw the processed image maintaining aspect ratio
            processedImage.draw(in: CGRect(origin: .zero, size: processedImage.size))
        }
        
        // Convert to PNG data with maximum quality
        guard let pngData = finalImage.pngData() else { return }
        
        // Create a temporary file URL with proper PNG extension
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent("background_removed_\(UUID().uuidString)").appendingPathExtension("png")
        
        do {
            try pngData.write(to: temporaryFileURL)
            
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, fileURL: temporaryFileURL, options: nil)
            } completionHandler: { success, error in
                try? FileManager.default.removeItem(at: temporaryFileURL)
                
                if let error = error {
                    print("Error saving image: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error saving temporary image: \(error.localizedDescription)")
        }
    }
    
    private func render(ciImage: CIImage) -> UIImage {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        // Create CGImage with original dimensions
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            fatalError("Failed to render CGImage")
        }
        
        // Get the original image's properties
        let originalScale: CGFloat
        let originalOrientation: UIImage.Orientation
        let size: CGSize
        
        if let originalImage = self.originalImage {
            originalScale = originalImage.scale
            originalOrientation = originalImage.imageOrientation
            size = originalImage.size
        } else {
            originalScale = UIScreen.main.scale
            originalOrientation = .up
            size = CGSize(width: cgImage.width, height: cgImage.height)
        }
        
        // Create a new image with proper alpha channel handling
        let format = UIGraphicsImageRendererFormat()
        format.scale = originalScale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let finalImage = renderer.image { context in
            // Fill with clear color first
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw the image maintaining aspect ratio
            UIImage(cgImage: cgImage, scale: originalScale, orientation: originalOrientation)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        
        return finalImage
    }
    
    private func apply(mask: CIImage, to image: CIImage) -> CIImage {
        // Ensure the mask is properly aligned with the input image
        let alignedMask = mask.transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
        
        // Create a filter group to handle transparency properly
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = alignedMask
        filter.backgroundImage = CIImage.empty()
        
        guard var outputImage = filter.outputImage else { return image }
        
        // Ensure proper alpha channel handling
        if let alphaFilter = CIFilter(name: "CIColorMatrix") {
            alphaFilter.setValue(outputImage, forKey: kCIInputImageKey)
            // Adjust alpha channel
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            
            if let alphaOutput = alphaFilter.outputImage {
                outputImage = alphaOutput
            }
        }
        
        // Ensure the output image maintains the original dimensions
        if outputImage.extent != image.extent {
            outputImage = outputImage.cropped(to: image.extent)
        }
        
        return outputImage
    }
    
    private func createMaskImage(from inputImage: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: inputImage)
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        do {
            try handler.perform([request])
            guard let mask = request.results?.first else { return nil }
            
            // Scale the mask to match the input image size
            let maskImage = CIImage(cvPixelBuffer: mask.pixelBuffer)
            let scaleX = inputImage.extent.width / maskImage.extent.width
            let scaleY = inputImage.extent.height / maskImage.extent.height
            
            let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            // Ensure the mask is positioned correctly
            let centerTransform = CGAffineTransform(translationX: inputImage.extent.minX, y: inputImage.extent.minY)
            return scaledMask.transformed(by: centerTransform)
        } catch {
            print("Error generating mask: \(error.localizedDescription)")
            return nil
        }
    }
}
