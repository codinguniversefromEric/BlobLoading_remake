//
//  BlobLoadingApp.swift
//  BlobLoading
//
//  Created by 魏嘉賢 on 2026/5/13.
//

import SwiftUI

@main
struct BlobLoadingApp: App {
    var body: some Scene {
        WindowGroup {
            // 呼叫主畫面 (ContentView 位於其他檔案)
            ContentView()
        }
    }
}

struct BlobLoading: View {
    // 物理引擎大腦：使用 @State 讓 TimelineView 驅動，避免 Canvas 渲染時的無窮迴圈
    @State private var blobSystem = BlobSystem4()
    
    var body: some View {
        // 【動態佈局層】
        // 使用 GeometryReader 獲取當前裝置（iPhone SE ~ Pro Max、iPad）的精確尺寸與安全區域
        GeometryReader { proxy in
            let size = proxy.size
            let safeTop = proxy.safeAreaInsets.top
            
            // ==========================================
            // 📐 動態座標與尺寸計算 (相對於 Canvas 絕對中心點 0,0)
            // ==========================================
            
            // 1. 頂部牽引池 (動態島位置)：螢幕最上方 (-size.height / 2) 加上頂部安全距離，再往上微調 70 確保藏在島內
            let topAnchorY = -size.height / 2 + safeTop - 70
            
            // 2. 底部基座：設定在螢幕中心點偏下方，約螢幕總高度 35% 的位置
            let liquidBaseY = size.height * 0.35
            
            // 3. 液體最大高度：設定為螢幕總高度的 45% (配合基座位置，畫面比例最剛好)
            let maxLiquidHeight = size.height * 0.45
            
            ZStack {
                // 【動畫驅動層】
                // 產生連續的重繪訊號，以螢幕最高更新率 (60Hz/120Hz) 驅動流體動畫
                TimelineView(.animation) { timeline in
                    // 取得當前精確時間，用於物理引擎計算 Delta Time (時間差)
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    
                    ZStack {
                        // 【高效渲染層】
                        // Canvas 適合處理高強度的 2D 濾鏡與大量視圖印章
                        Canvas { context, canvasSize in
                            // 1. 將畫布量測好的動態邊界，傳入大腦 (物理系統) 進行座標與狀態更新
                            blobSystem.update(
                                date: time,
                                topBoundary: topAnchorY,
                                bottomBoundary: liquidBaseY,
                                maxHeight: maxLiquidHeight
                            )
                            
                            // 2. Metaball (元球) 視覺魔法：
                            // 先模糊邊緣，再用 Alpha 閾值把半透明交疊處「實體化」成純黑色，產生黏稠牽絲感
                            context.addFilter(.alphaThreshold(min: 0.35, color: .black))
                            context.addFilter(.blur(radius: 30))
                            
                            context.drawLayer { layer in
                                // 定義畫布的絕對中心點
                                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                                
                                // 蓋印章：Tag 2 頂部牽引池 (當預判進度滿了，會逐漸縮小至消失)
                                if blobSystem.topPoolScale > 0 {
                                    if let resolvedSymbol = context.resolveSymbol(id: 2) {
                                        layer.draw(resolvedSymbol, at: center)
                                    }
                                }
                                
                                // 蓋印章：Tag 0 底部基座
                                if let resolvedSymbol = context.resolveSymbol(id: 0) { layer.draw(resolvedSymbol, at: center) }
                                
                                // 蓋印章：所有掉落中的水滴
                                for id in blobSystem.blobs.map({ $0.id }) {
                                    if let resolvedSymbol = context.resolveSymbol(id: id) { layer.draw(resolvedSymbol, at: center) }
                                }
                                
                                // 蓋印章：Tag 1 向上生長的主液體柱
                                if let resolvedSymbol = context.resolveSymbol(id: 1) { layer.draw(resolvedSymbol, at: center) }
                            }
                        } symbols: {
                            // 【印章定義區】(這裡的 View 不會直接顯示，而是交給 Canvas 蓋章用)
                            
                            // Tag 0: 底部基座
                            Capsule()
                                .frame(width: 115, height: 20)
                                .offset(y: liquidBaseY)
                                .tag(0)
                            
                            // Tag 1: 主液體柱
                            // 核心：高度由系統決定，Y 軸往下推 (liquidBaseY - 高度的一半) 來確保底部永遠貼齊基座
                            Rectangle()
                                .frame(width: 100, height: blobSystem.liquidHeight)
                                .offset(y: liquidBaseY - blobSystem.liquidHeight / 2)
                                .tag(1)
                            
                            // Tag 2: 頂部牽引池 (動態島母體)
                            // 綁定 topPoolScale，當最後一滴水產出時，母體會平滑萎縮，產生水被抽乾的真實物理感
                            if blobSystem.topPoolScale > 0 {
                                Capsule()
                                    .frame(
                                        width: 140 * blobSystem.topPoolScale,
                                        height: 30 * blobSystem.topPoolScale
                                    )
                                    .offset(y: topAnchorY)
                                    .tag(2)
                            }
                            
                            // 動態生成的所有水滴
                            ForEach(blobSystem.blobs, id: \.self) { blob in
                                Circle()
                                    .frame(width: blob.size, height: blob.size)
                                    .offset(x: blob.x, y: blob.y)
                                    .tag(blob.id)
                            }
                        }
                        
                        // 進度百分比文字 (獨立於 Canvas 濾鏡之外，確保清晰)
                        Text("\(Int(blobSystem.progress))%")
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .shadow(color: .white, radius: 2) // 白色陰影避免與黑色液體融為一體
                    }
                }
                .mask(
                    // 巨型遮罩：確保軌跡從動態島一路涵蓋到螢幕下方，不會被中途裁切
                    Capsule()
                        .frame(width: 110, height: size.height * 1.5)
                        .offset(y: -size.height * 0.2)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea() // 突破安全區域，直達螢幕最頂端邊界
        }
    }
}

// 資料結構：代表單一水滴的狀態
struct Blob: Identifiable, Hashable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: CGFloat
}

// 【物理引擎大腦】：完全不包含 View，純粹處理數學、碰撞與進度預判
class BlobSystem4 {
    var progress: Double = 0          // 畫面顯示的真實進度 (0~100)
    var blobs: [Blob] = []            // 畫面上存在的水滴陣列
    var liquidHeight: CGFloat = 0     // 主液體柱的實際像素高度
    
    var expectedProgress: Double = 0  // 【預判系統】未來水滴吸收後的總進度，用來決定何時停止生成
    var topPoolScale: CGFloat = 1.0   // 頂部水池的縮放比例 (1.0 = 正常, 0.0 = 乾涸消失)
    
    private var lastUpdate: TimeInterval = 0
    private var spawnTimer: TimeInterval = 0
    
    func update(date: TimeInterval, topBoundary: CGFloat, bottomBoundary: CGFloat, maxHeight: CGFloat) {
        // 1. 計算幀間時間差 (Delta Time)
        if lastUpdate == 0 { lastUpdate = date }
        let dt = date - lastUpdate
        lastUpdate = date
        
        // 2. 根據「真實進度」轉換出當前液柱的實際像素高度
        liquidHeight = maxHeight * (CGFloat(progress) / 100.0)
        
        spawnTimer += dt
        
        // 3. 【水滴生成與預判邏輯】
        // 條件：計時器滿了，且「預估總進度」還沒達到 100%
        if spawnTimer > 0.12 && expectedProgress < 100 {
            spawnTimer = 0
            
            let dropSize = CGFloat.random(in: 25...42)
            let newBlob = Blob(
                x: CGFloat.random(in: -8...8),
                y: topBoundary - 10,  // 出生在頂部錨點稍微上方，確保初始狀態被隱藏
                size: dropSize,
                speed: CGFloat.random(in: 140...220)
            )
            blobs.append(newBlob)
            
            // 核心：水滴一誕生，就先預先加總它未來會貢獻的進度量
            expectedProgress += Double(dropSize * 0.05)
        }
        
        // 4. 【頂部水池乾涸動畫】
        // 當預估進度達標，代表「最後一滴水」已誕生，開始平滑縮小母體，創造收尾視覺
        if expectedProgress >= 100 {
            topPoolScale -= CGFloat(dt * 3.0)
            if topPoolScale < 0 { topPoolScale = 0 }
        }
        
        // 5. 計算液面碰撞的絕對 Y 座標 (底部基準減去當前高度)
        let liquidTop = bottomBoundary - liquidHeight
        
        // 6. 【下落與吸收邏輯】
        for i in blobs.indices {
            // 等速自由落體
            blobs[i].y += blobs[i].speed * dt
            
            // 當水滴落入液面下方 (加上 -40 的緩衝區，提早觸發表面張力效果)
            if blobs[i].y > liquidTop - 40 {
                // 視覺層：水滴尺寸呈指數衰減，產生被液面快速吸入的錯覺
                blobs[i].size *= 0.82
                
                // 數值層：水滴縮小的同時，逐步推進真實進度條
                if progress < 100 {
                    progress += Double(blobs[i].size * 0.015)
                }
            }
        }
        
        // 7. 防呆機制與垃圾回收
        if progress > 100 { progress = 100 }
        // 當水滴因為高斯模糊而被閾值濾鏡切斷，且視覺上已經不可見時 (size < 6)，徹底從記憶體移除
        blobs.removeAll { $0.size < 6 }
    }
}
