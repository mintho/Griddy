//
//  TabBarView.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 20.04.25.
//

import SwiftUI

struct TabBarView: View {
    @Binding var openFiles: [FileState]
    @Binding var selectedTabId: UUID?
    let closeTabAction: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openFiles) { fileState in
                    TabButton(
                        fileState: fileState,
                        isSelected: fileState.id == selectedTabId,
                        selectAction: {
                            selectedTabId = fileState.id
                        },
                        closeAction: {
                            closeTabAction(fileState.id)
                        }
                    )
                    .tag(fileState.id)
                }
            }
            .padding(.leading, 5)
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
}
