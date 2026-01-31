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
        VStack(spacing: 18) {

            Spacer().frame(height: 10)

            // Friendly face
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 200, height: 200)
                .overlay(Text("😊").font(.system(size: 86)))
                .overlay(
                    Circle()
                        .stroke(voiceManager.isListening ? Color.orange : Color.clear, lineWidth: 4)
                )

            // Conversation preview
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(voiceManager.messages.indices, id: \.self) { i in
                        let m = voiceManager.messages[i]
                        HStack {
                            if m.role == .user { Spacer() }
                            Text(m.text)
                                .padding(12)
                                .background(m.role == .user ? Color.orange.opacity(0.25) : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            if m.role == .assistant { Spacer() }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 220)

            Text(voiceManager.statusText)
                .font(.callout)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                voiceManager.toggleListening()
            } label: {
                Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
                    .padding(26)
                    .background(voiceManager.isListening ? Color.red : Color.orange)
                    .clipShape(Circle())
            }
            .padding(.bottom, 24)

        }
        .onAppear {
            voiceManager.requestPermissionsOnly()
        }
    }
}

#Preview {
    ContentView();
}

