//
//  ContentView.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-30.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var voiceManager = VoiceManager()

    var body: some View {
        VStack(spacing: 32) {

            Spacer()

            // Friendly face
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 220, height: 220)
                .overlay(
                    Text("😊")
                        .font(.system(size: 90))
                )
                .overlay(
                    Circle()
                        .stroke(voiceManager.isListening ? Color.orange : Color.clear, lineWidth: 4)
                )

            Text(voiceManager.statusText)
                .font(.title3)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // 🎤 Mic Button
            Button(action: {
                voiceManager.toggleListening()
            }) {
                Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .padding(28)
                    .background(voiceManager.isListening ? Color.red : Color.orange)
                    .clipShape(Circle())
            }

            Spacer()
        }
        .onAppear {
            voiceManager.requestPermissionsOnly()
        }
    }
}



#Preview {
    ContentView();
}

