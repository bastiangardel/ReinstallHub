//
//  ReinstallHubApp.swift
//  ReinstallHub
//
//  Created by Bastian Gardel on 11.11.2024.
//

import Foundation
import CoreData
import KeychainAccess
import LocalAuthentication
import SwiftUI

struct DeviceResponse: Decodable {
    let device: [Device]
    
    enum CodingKeys: String, CodingKey {
        case device = "Device"
    }
}

struct Device: Identifiable, Decodable, Hashable, Equatable {
    // Utilisez 'id' comme identifiant unique
    let id: Int  // Cette valeur provient de "DeviceId" dans le JSON
    let friendlyName: String
    let dateTagged: String
    let deviceUuid: String
    
    enum CodingKeys: String, CodingKey {
        case id = "DeviceId"         // Mappage de "DeviceId" du JSON vers "id" dans le modèle
        case friendlyName = "FriendlyName"
        case dateTagged = "DateTagged"
        case deviceUuid = "DeviceUuid"
    }
}

enum AppError: Error {
    case configurationMissing
    case invalidResponse
}

enum KeychainKeys: String {
    case apiUsername = "WorkspaceOneAPIUsername"
    case apiPassword = "WorkspaceOneAPIPassword"
    case apiKey = "WorkspaceOneAPIKey"
}

let keychain = Keychain(service: "ch.epfl.reinstallhub")

func saveCredentials(username: String, password: String, apiKey: String) {
    keychain[KeychainKeys.apiUsername.rawValue] = username
    keychain[KeychainKeys.apiPassword.rawValue] = password
    keychain[KeychainKeys.apiKey.rawValue] = apiKey
}

func getCredentials() -> (username: String, password: String, apiKey: String)? {
    guard let username = keychain[KeychainKeys.apiUsername.rawValue],
          let password = keychain[KeychainKeys.apiPassword.rawValue],
          let apiKey = keychain[KeychainKeys.apiKey.rawValue] else {
        return nil
    }
    return (username, password, apiKey)
}

func saveToCoreData(url: String, appId: String, tagid: String) {
    let context = PersistenceController.shared.container.viewContext
    let config = AppConfig(context: context)
    config.wsoUrl = url
    config.appId = appId
    config.tagid = tagid
    
    do {
        try context.save()
    } catch {
        print("Erreur lors de la sauvegarde des données dans Core Data: \(error)")
    }
}

func getAppConfig() -> AppConfig? {
    let context = PersistenceController.shared.container.viewContext
    let request: NSFetchRequest<AppConfig> = AppConfig.fetchRequest()
    return try? context.fetch(request).first
}

struct ConfigurationView: View {
    @Binding var isConfigured: Bool
    @State private var wsoUrl: String = ""
    @State private var appId: String = ""
    @State private var tagId: String = ""
    @State private var apiKey: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    
    var body: some View {
        VStack {
            TextField("URL du tenant WSO", text: $wsoUrl)
            TextField("App ID", text: $appId)
            TextField("Tag ID", text: $tagId)
            SecureField("API Key", text: $apiKey)
            TextField("API Username", text: $username)
            SecureField("API Password", text: $password)
            Button("Enregistrer") {
                saveConfiguration()
            }
        }
        .padding()
    }
    
    func saveConfiguration() {
        saveToCoreData(url: wsoUrl, appId: appId, tagid: tagId)
        saveCredentials(username: username, password: password, apiKey: apiKey)
        isConfigured = true
    }
}

func fetchDevices(withTag tag: String, completion: @escaping (Result<[Device], Error>) -> Void) {
    guard let config = getAppConfig(), let credentials = getCredentials() else {
        completion(.failure(AppError.configurationMissing))
        return
    }
    
    let url = URL(string: "\(config.wsoUrl ?? "url missing")/api/mdm/tags/\(tag)/devices")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(credentials.apiKey, forHTTPHeaderField: "aw-tenant-code")
    
    let loginString = "\(credentials.username):\(credentials.password)"
    let loginData = loginString.data(using: .utf8)
    let base64LoginString = loginData?.base64EncodedString() ?? ""
    request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    print(request)
    
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        
        // Imprimer la réponse brute
        if let data = data {
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Réponse brute : \(rawResponse)")  // Affiche la réponse JSON brute dans la console
                
                // Optionnel : Si vous voulez aussi le décoder et travailler avec les données
                do {
                    let decoder = JSONDecoder()
                    let decodedResponse = try decoder.decode(DeviceResponse.self, from: data)
                    
                    if decodedResponse.device.isEmpty {
                        print("Aucun appareil trouvé.")
                    } else {
                        print("Appareils récupérés : \(decodedResponse.device)")
                    }
                    
                    // Passez les appareils décodés à la fonction de completion
                    completion(.success(decodedResponse.device))
                    //completion(.success(dummyDevices))
                } catch {
                    print("Erreur de décodage : \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    task.resume()
}

func clearStorage() {
    // Effacer Core Data
    let context = PersistenceController.shared.container.viewContext
    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = AppConfig.fetchRequest()
    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    
    do {
        try context.execute(deleteRequest)
        try context.save()
    } catch {
        print("Erreur lors de la suppression des données dans Core Data: \(error)")
    }
    
    // Effacer Keychain
    do {
        try keychain.removeAll()
    } catch let error {
        print("Erreur lors de la suppression des informations du Keychain: \(error)")
    }
}

struct DeviceListView: View {
    @State private var devices: [Device] = []
    @State private var selectedDevices: Set<Device> = []
    @State private var statusMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var isAuthenticated = false
    @AppStorage("isConfigured") private var isConfigured: Bool = true
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Chargement en cours…")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                List(devices, id: \.id, selection: $selectedDevices) { device in
                    Text(device.friendlyName).tag(device)
                }
            }
            Text(statusMessage)
                .foregroundColor(.red)
                .padding()
            
                .toolbar {
                    HStack {
                        Button("Réinstaller le Hub") {
                            reinstallHubOnSelectedDevices()
                        }
                        .disabled(selectedDevices.isEmpty)
                        
                        Button("Rafraîchir") {
                            refreshDeviceList()
                        }
                        .disabled(!isAuthenticated)
                        
                        Button("Reset Authentification") {
                            clearStorage()
                            isConfigured = false // Retour à l'écran de configuration
                        }
                        
                        Button("Quitter") {
                            NSApp.terminate(nil)
                        }
                        
                    }
                }
        }
        .onAppear {
            //refreshDeviceList()
            if isAuthenticated {
                refreshDeviceList()
            }
            else{
                authenticateUser()
            }
        }
    }
    
    func authenticateUser() {
           let context = LAContext()
           var error: NSError?
           
           // Vérifier si l'authentification biométrique est disponible
           if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
               // Demander l'authentification biométrique
               context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Veuillez vous authentifier pour accéder aux appareils") { success, authenticationError in
                   DispatchQueue.main.async {
                       if success {
                           isAuthenticated = true
                           refreshDeviceList() // Authentification réussie, charger les appareils
                       } else {
                           statusMessage = authenticationError?.localizedDescription ?? ""
                       }
                   }
               }
           } else {
               // Biométrie non disponible, afficher une erreur
               statusMessage = "La biométrie n'est pas disponible sur cet appareil."
           }
       }
    
    func reinstallHubOnSelectedDevices() {
        isLoading = true
        statusMessage = "Réinstallation en cours…"
        let deviceIds = selectedDevices.map { $0.id }
        for deviceId in deviceIds {
            reinstallHub(deviceId: deviceId) { success in
                DispatchQueue.main.async {
                    if success {
                        statusMessage = "Réinstallation réussie pour l'appareil \(deviceId)"
                    } else {
                        statusMessage = "Erreur lors de la réinstallation pour l'appareil \(deviceId)"
                    }
                    isLoading = false
                }
            }
        }
    }
    
    private func refreshDeviceList() {
        guard let config = getAppConfig() else { return }
        isLoading = true
        statusMessage = ""
        fetchDevices(withTag: config.tagid ?? "Missing Tag ID") { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedDevices):
                    devices = fetchedDevices
                    
                    if(devices.isEmpty)
                    {
                        statusMessage = "Aucun mac trouvé avec hub manquant"
                    }
                    else
                    {
                        statusMessage = "Appareils chargés avec succès."
                    }
                case .failure(let error):
                    statusMessage = "Erreur de chargement : \(error.localizedDescription)"
                }
                isLoading = false
            }
        }
    }
}

func reinstallHub(deviceId: Int, completion: @escaping (Bool) -> Void) {
    guard let config = getAppConfig(), let credentials = getCredentials() else { return }
    
    let url = URL(string: "\(config.wsoUrl ?? "url missing")/api/mam/apps/internal/\(config.appId ?? "appid missing")/install")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(credentials.apiKey, forHTTPHeaderField: "aw-tenant-code")
    
    let loginString = "\(credentials.username):\(credentials.password)"
    let loginData = loginString.data(using: .utf8)
    let base64LoginString = loginData?.base64EncodedString() ?? ""
    request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    do {
        let body: [String: Any] = ["DeviceId": String(deviceId)]
        let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
              print("Contenu de jsonData: \(jsonString)")
          }
        
        request.httpBody = jsonData
        
        print(url)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(false)
                return
            }
            completion(true)
        }
        task.resume()
    } catch {
        print("Erreur de sérialisation JSON: \(error.localizedDescription)")
    }
}

@main
struct ReinstallHubApp: App {
    @AppStorage("isConfigured") private var isConfigured: Bool = false
    
    var body: some Scene {
        WindowGroup {
            if isConfigured {
                DeviceListView()
            } else {
                ConfigurationView(isConfigured: $isConfigured)
            }
        }
    }
}
