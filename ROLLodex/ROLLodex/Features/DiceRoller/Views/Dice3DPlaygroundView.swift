//  Dice3DPlaygroundView.swift
//
//  Legacy SceneKit sandbox screen — NOT reachable from the app's TabView.
//  Kept for geometry/physics experiments. The production engine it drives
//  lives in DiceSceneController.swift; now that the split is done, this file
//  is a deletion candidate (remove via Xcode when convenient).

import SwiftUI
import SceneKit
import simd

// MARK: - SwiftUI

struct Dice3DPlaygroundView: View {
    @State private var controller = DiceSceneController()
    @State private var diceCount = 1
    @State private var diceKind: Dice3DKind = .d6
    @State private var results: [Int?] = [nil]
    @State private var isRolling = false

    private let maxDice = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    SceneKitView(controller: controller)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

                    if let total = totalResult {
                        Text("\(total)")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 20)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)

                Picker("Kind", selection: $diceKind) {
                    // Compound kinds (d100) need formula context to spawn pairs and
                    // wire connectors, so the legacy playground picker only offers
                    // standalone kinds. The main DiceRollerView still surfaces d100.
                    ForEach(Dice3DKind.allCases.filter(\.isStandalone)) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRolling)

                HStack {
                    Text("Dice")
                        .font(.headline)
                    Spacer()
                    Stepper("\(diceCount)", value: $diceCount, in: 1...maxDice)
                        .labelsHidden()
                    Text("\(diceCount)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 24)
                }
                .disabled(isRolling)

                Button {
                    rollAll()
                } label: {
                    Label(isRolling ? "Rolling…" : "Roll \(diceCount)\(diceKind.rawValue)", systemImage: "dice.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRolling)
            }
            .padding()
            .navigationTitle("3D Dice (sandbox)")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: results)
            .onAppear {
                controller.setDice(count: diceCount, kind: diceKind)
                controller.onDieSettled = { @MainActor index, face in
                    guard results.indices.contains(index) else { return }
                    results[index] = face
                }
            }
            .onChange(of: diceCount) { _, new in
                controller.setDice(count: new, kind: diceKind)
                results = Array(repeating: nil, count: new)
            }
            .onChange(of: diceKind) { _, new in
                controller.setDice(count: diceCount, kind: new)
                results = Array(repeating: nil, count: diceCount)
            }
        }
    }

    private func rollAll() {
        results = Array(repeating: nil, count: diceCount)
        isRolling = true
        controller.rollAll { @MainActor _ in
            isRolling = false
        }
    }

    private var totalResult: Int? {
        let settled = results.compactMap { $0 }
        return settled.isEmpty ? nil : settled.reduce(0, +)
    }
}

