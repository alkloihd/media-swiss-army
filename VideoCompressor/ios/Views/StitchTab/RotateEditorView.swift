//
//  RotateEditorView.swift
//  VideoCompressor
//
//  Simple 4-stop rotation picker (0 / 90 / 180 / 270 degrees clockwise).
//  Active stop is highlighted with the accent color. Draft edits are only
//  committed to StitchProject when the parent ClipEditorSheet taps Done.
//

import SwiftUI

struct RotateEditorView: View {
    @Binding var edits: ClipEdits

    private static let stops: [Int] = [0, 90, 180, 270]

    var body: some View {
        VStack(spacing: 24) {
            Text("\(edits.rotationDegrees)°")
                .font(.system(size: 56, weight: .light))
                .monospacedDigit()
                .padding(.top, 24)

            HStack(spacing: 12) {
                ForEach(Self.stops, id: \.self) { deg in
                    Button {
                        edits.rotationDegrees = deg
                    } label: {
                        Text("\(deg)°")
                            .font(.title3.weight(.semibold))
                            .frame(width: 64, height: 44)
                            .background(
                                deg == edits.rotationDegrees
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15)
                            )
                            .foregroundStyle(
                                deg == edits.rotationDegrees ? Color.white : Color.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }
}
