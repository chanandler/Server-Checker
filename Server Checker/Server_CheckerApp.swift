//
//  Server_CheckerApp.swift
//  Server Checker
//
//  Created by Clint Yarwood on 16/10/2025.
//

import SwiftUI

@main
struct Server_CheckerApp: App {
    @StateObject private var store = ServerStore()
    
    var body: some Scene {
        WindowGroup {
            ServerListView().environmentObject(store)
        }
    }
}
