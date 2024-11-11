//
//  ReinstallHubApp.swift
//  ReinstallHub
//
//  Created by Bastian Gardel on 11.11.2024.
//

import SwiftUI
import Foundation
import Security

import Foundation

struct Device: Identifiable, Hashable, Decodable {
    let id: UUID // Identifiant unique de l'appareil
    let name: String
    let udid: String // UDID pour l'API, utilisé pour la réinstallation du Hub
}

class APIManager {
    let baseURL = "https://as.awmdm.com/api"

    private var credentials: String? {
        KeychainHelper.shared.retrieveValue(forKey: "credentials")
    }

    private var apiKey: String? {
        KeychainHelper.shared.retrieveValue(forKey: "apiKey")
    }

    // Récupère les appareils avec le tag "Missing Hub"
    func fetchDevicesWithTag(completion: @escaping ([Device]?) -> Void) {
        guard let credentials = credentials, let apiKey = apiKey else {
            print("Erreur : les identifiants ne sont pas présents dans le Keychain")
            completion(nil)
            return
        }

        let url = URL(string: "\(baseURL)/mdm/devices/search?tag=Missing Hub&organizationgroupcode=SSC")!
        var request = URLRequest(url: url)
        request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.addValue(apiKey, forHTTPHeaderField: "aw-tenant-code")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Erreur: \(error?.localizedDescription ?? "Pas de description")")
                completion(nil)
                return
            }
            
            let devices = try? JSONDecoder().decode([Device].self, from: data)
            completion(devices)
        }.resume()
    }

    // Lancer la réinstallation du Hub sur un appareil via son UDID
    func installHub(on udid: String) {
        guard let credentials = credentials, let apiKey = apiKey else {
            print("Erreur : les identifiants ne sont pas présents dans le Keychain")
            return
        }

        let url = URL(string: "\(baseURL)/mam/apps/internal/284/install")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.addValue(apiKey, forHTTPHeaderField: "aw-tenant-code")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["Udid": udid] // Utilisation du UDID pour la réinstallation
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Erreur lors de la réinstallation du Hub : \(error)")
            } else {
                print("Réinstallation du Hub lancée sur \(udid)")
            }
        }.resume()
    }
}

struct DeviceListView: View {
    @State private var showCredentialsInput = false
    @State private var devices: [Device] = [] // Liste des appareils
    @State private var selectedDevices: Set<Device> = [] // Appareils sélectionnés

    var body: some View {
        VStack {
            List(devices, selection: $selectedDevices) { device in
                Text(device.name) // Affichage du nom de l'appareil
            }
            .frame(minWidth: 400, minHeight: 300)

            Button("Réinstaller le Hub") {
                reinstallHubOnSelectedDevices()
            }
            .disabled(selectedDevices.isEmpty) // Désactive le bouton si aucun appareil n'est sélectionné
        }
        .onAppear {
            checkCredentials()
            fetchDevices()
        }
        .sheet(isPresented: $showCredentialsInput) {
            CredentialsInputView(isPresented: $showCredentialsInput) { encodedCredentials, apiKey in
                KeychainHelper.shared.save(value: encodedCredentials, forKey: "credentials")
                KeychainHelper.shared.save(value: apiKey, forKey: "apiKey")
            }
        }
    }

    private func checkCredentials() {
        let credentials = KeychainHelper.shared.retrieveValue(forKey: "credentials")
        let apiKey = KeychainHelper.shared.retrieveValue(forKey: "apiKey")
        
        if credentials == nil || apiKey == nil {
            showCredentialsInput = true
        }
    }

    private func fetchDevices() {
        APIManager().fetchDevicesWithTag { devices in
            DispatchQueue.main.async {
                self.devices = devices ?? []
            }
        }
    }

    private func reinstallHubOnSelectedDevices() {
        for device in selectedDevices {
            APIManager().installHub(on: device.udid) // Utilisation du UDID pour la réinstallation
        }
    }
}

struct CredentialsInputView: View {
    @Binding var isPresented: Bool
    var onSave: (String, String) -> Void

    @State private var login: String = ""
    @State private var password: String = ""
    @State private var apiKey: String = ""

    var body: some View {
        VStack {
            TextField("Login", text: $login)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("Password", text: $password)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("API Key", text: $apiKey)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button("Save") {
                saveCredentials()
            }
            .padding()
        }
        .padding()
    }

    private func saveCredentials() {
        let loginPassword = "\(login):\(password)"
        if let encodedCredentials = loginPassword.data(using: .utf8)?.base64EncodedString() {
            onSave(encodedCredentials, apiKey)
            isPresented = false
        }
    }
}

class KeychainHelper {
    static let shared = KeychainHelper()
    
    func save(value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        delete(forKey: key) // Supprimez toute valeur précédente
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func retrieveValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

@main
struct ReinstallHubApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
