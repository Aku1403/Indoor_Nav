//
//  NaVITgationApp.swift
//  NaVITgation
//
//  Created by AKANKSHA SHARMA on 12/09/25.
//

import SwiftUI
@main
struct NaVITgationApp: App {
    @State private var showWelcome = true

        var body: some Scene {
            WindowGroup {
                ZStack {
                    ContentView()
                        .opacity(showWelcome ? 0 : 1)   // fade in/out
                    if showWelcome {
                        WelcomeView()
                            .transition(.opacity)       // or .slide
                    }
                }
                .animation(.easeInOut(duration: 2), value: showWelcome)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showWelcome = false }
                    }
                }
            }
        }
}
