//
//  WelcomeView.swift
//  NaVITgation
//
//  Created by AKANKSHA SHARMA on 12/09/25.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Welcome!")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
