//
//  ContentView.swift
//  removebg
//
//  Created by Aarav Gupta on 18/01/25.
//

import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingPhotoPicker = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    var manager: BGRemovalManager = .init()
    
    var body: some View {
        NavigationStack {
            if let image = manager.processedImage {
                // Main editing view
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    EditingView(
                        image: image,
                        hasRemovedBackground: manager.hasRemovedBackground,
                        isProcessing: manager.isProcessing,
                        onRemoveBackground: { manager.createSticker() },
                        onReset: {
                            manager.processedImage = manager.originalImage
                            manager.hasRemovedBackground = false
                        }
                    )
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            manager.processedImage = nil
                        }
                        .foregroundStyle(.white)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if manager.hasRemovedBackground {
                            Button("Done") {
                                manager.saveImageToPhotos()
                                showingSaveSuccess = true
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        }
                    }
                }
                .alert("Saved to Photos", isPresented: $showingSaveSuccess) {
                    Button("OK", role: .cancel) {}
                }
            } else {
                // Show CustomPhotoPickerView directly
                CustomPhotoPickerView { image in
                    manager.processedImage = image
                    manager.originalImage = image
                    manager.hasRemovedBackground = false
                }
            }
        }
    }
}

struct EditingView: View {
    let image: UIImage
    let hasRemovedBackground: Bool
    let isProcessing: Bool
    let onRemoveBackground: () -> Void
    let onReset: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    var hasAlpha: Bool {
        guard let cgImage = image.cgImage else { return false }
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .first || 
               alphaInfo == .last || 
               alphaInfo == .premultipliedFirst || 
               alphaInfo == .premultipliedLast
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Image area
                ZStack {
                    if hasAlpha {
                        CheckerboardBackground()
                    }
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale * magnifyBy)
                        .gesture(
                            MagnificationGesture()
                                .updating($magnifyBy) { currentState, gestureState, _ in
                                    gestureState = currentState
                                }
                                .onEnded { value in
                                    scale *= value
                                    scale = min(max(scale, 1), 3)
                                }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom toolbar
                VStack(spacing: 20) {
                    // Action buttons
                    HStack(spacing: 24) {
                        if !hasRemovedBackground {
                            Button(action: onRemoveBackground) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 50, height: 50)
                                        
                                        if isProcessing {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                        } else {
                                            Image(systemName: "person.and.background.dotted")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text("Remove")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }
                            }
                            .disabled(isProcessing)
                        }
                        
                        if hasRemovedBackground {
                            Button(action: onReset) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white)
                                    }
                                    Text("Reset")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Bottom safe area
                    Rectangle()
                        .fill(.clear)
                        .frame(height: geometry.safeAreaInsets.bottom)
                }
                .background {
                    Rectangle()
                        .fill(.black.opacity(0.8))
                        .ignoresSafeArea()
                }
            }
        }
    }
}

struct EmptyStateView: View {
    let isLoading: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Processing Image...")
                    .foregroundStyle(.white)
            } else {
                Button(action: onTap) {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                        
                        Text("Select a Photo")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct CheckerboardBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 8
            let rows = Int(size.height / tileSize) + 1
            let columns = Int(size.width / tileSize) + 1
            
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(
                        x: CGFloat(column) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    
                    if (row + column).isMultiple(of: 2) {
                        context.fill(
                            Path(rect),
                            with: .color(colorScheme == .dark ? 
                                .gray.opacity(0.2) : 
                                .gray.opacity(0.1))
                        )
                    } else {
                        context.fill(
                            Path(rect),
                            with: .color(colorScheme == .dark ? 
                                .gray.opacity(0.1) : 
                                .white)
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
