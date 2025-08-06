//
//  LoadingView.swift
//  Django Files
//
//  Created by Ralph Luaces on 8/4/25.
//

import SwiftUI

struct LoadingView: View {
    @State private var isLoading = false
    @State private var firstAppear = false

    var body: some View {
        ZStack{
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(Color.launchScreenBackground, lineWidth: 5)
                .rotationEffect(Angle(degrees: isLoading ? 360 : 0))
                .opacity(firstAppear ? 1 : 0)
                .onAppear {
                    DispatchQueue.main.async {
                        if isLoading == false {
                            withAnimation(
                                .linear(duration: 1).repeatForever(
                                    autoreverses: false
                                )
                            ) {
                                isLoading.toggle()
                            }
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            firstAppear = true
                        }
                    }
                }
                .onDisappear {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            firstAppear = true
                        }
                    }
                }
        }
    }
}
