//
//  ReinstallHubApp.swift
//  ReinstallHub
//
//  Created by Bastian Gardel on 11.11.2024.
//

import SwiftUI
import Foundation
import AuthenticationServices

import Foundation

struct Device: Identifiable, Hashable, Decodable {
    let id: UUID // Identifiant unique de l'appareil
    let name: String
    let udid: String // UDID pour l'API, utilisé pour la réinstallation du Hub
}


class APIManager {

    private let baseURL = "https://as.awmdm.com/api/mam/apps/internal/284/install"

    // Fonction pour récupérer les appareils avec le tag "Missing Hub"
    func fetchDevicesWithTag(completion: @escaping ([Device]?) -> Void) {
        // Récupérer les identifiants depuis le Keychain
        if let credentials = KeychainHelper.shared.retrievePassword(for: "WorkspaceOneCredentials") {
            let loginPassword = credentials.username
            let apiKey = credentials.password

            // Effectuer la requête API avec les identifiants récupérés
            fetchDevices(loginPassword: loginPassword, apiKey: apiKey, completion: completion)
        } else {
            completion(nil)
        }
    }

    private func fetchDevices(loginPassword: String, apiKey: String, completion: @escaping ([Device]?) -> Void) {
        guard let url = URL(string: baseURL) else {
            print("URL invalide")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Préparer l'en-tête d'authentification Basic (Base64)
        let authString = "Basic \(loginPassword)"
        request.setValue(authString, forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "aw-tenant-code")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Erreur lors de la récupération des appareils: \(error)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("Données manquantes")
                completion(nil)
                return
            }

            // Analyser la réponse en JSON
            do {
                let devices = try JSONDecoder().decode([Device].self, from: data)
                completion(devices)
            } catch {
                print("Erreur lors de la décodification des données: \(error)")
                completion(nil)
            }
        }

        task.resume()
    }

    func installHub(on udid: String) {
        if let credentials = KeychainHelper.shared.retrievePassword(for: "WorkspaceOneCredentials") {
            let loginPassword = credentials.username
            let apiKey = credentials.password

            reinstallHub(udid: udid, loginPassword: loginPassword, apiKey: apiKey)
        }
    }

    private func reinstallHub(udid: String, loginPassword: String, apiKey: String) {
        guard let url = URL(string: baseURL) else {
            print("URL invalide")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Préparer le corps de la requête
        let body: [String: Any] = ["Udid": udid]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        // Ajouter les en-têtes d'authentification
        let authString = "Basic \(loginPassword)"
        request.setValue(authString, forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "aw-tenant-code")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Erreur lors de la réinstallation du Hub: \(error)")
                return
            }

            if let data = data {
                print("Réponse reçue : \(String(data: data, encoding: .utf8) ?? "Aucune donnée")")
            }
        }

        task.resume()
    }
}

struct DeviceListView: View {
       @State private var isAuthenticated = false
       @State private var login = ""
       @State private var password = ""
       @State private var apiKey = ""
       @State private var devices: [Device] = []
       @State private var isLoading = false
       @State private var showLoginPopup = false
       @State private var selectedDevices = Set<String>()
       
       // Vérification de l'authentification à l'ouverture de l'app
       init() {
           if KeychainHelper.shared.retrievePassword(for: "WorkspaceOneCredentials") != nil {
               self._isAuthenticated.wrappedValue = true
           } else {
               self._showLoginPopup.wrappedValue = true
           }
       }

       var body: some View {
           VStack {
               if isAuthenticated {
                   // Liste des appareils récupérés via l'API
                   List(devices, id: \.udid, selection: $selectedDevices) { device in
                       Text(device.name)
                           .padding()
                           .background(selectedDevices.contains(device.udid) ? Color.blue : Color.clear)
                           .cornerRadius(5)
                           .foregroundColor(.black)
                   }
                   
                   // Bouton pour réinstaller le Hub sur les appareils sélectionnés
                   Button("Réinstaller le Hub") {
                       reinstallHubOnSelectedDevices()
                   }
                   .disabled(selectedDevices.isEmpty)
                   .padding()
                   .background(selectedDevices.isEmpty ? Color.gray : Color.blue)
                   .foregroundColor(.white)
                   .cornerRadius(10)
                   
                   // Indicateur de chargement
                   if isLoading {
                       ProgressView()
                           .progressViewStyle(CircularProgressViewStyle())
                           .padding()
                   }
               } else {
                   // Affichage du bouton pour afficher le popup de connexion
                   Button("Se connecter") {
                       self.showLoginPopup.toggle()
                   }
                   .padding()
                   .background(Color.blue)
                   .foregroundColor(.white)
                   .cornerRadius(10)
                   .sheet(isPresented: $showLoginPopup) {
                       LoginPopupView(login: $login, password: $password, apiKey: $apiKey, isAuthenticated: $isAuthenticated)
                   }
               }
           }
           .onAppear {
               if isAuthenticated {
                   loadDevices()
               }
           }
       }

       // Fonction pour charger les appareils
       private func loadDevices() {
           guard !login.isEmpty, !password.isEmpty, !apiKey.isEmpty else { return }
           isLoading = true
           let loginPassword = "\(login):\(password)"
           
           let apiManager = APIManager()
           apiManager.fetchDevicesWithTag { devices in
               DispatchQueue.main.async {
                   self.devices = devices ?? []
                   self.isLoading = false
               }
           }
       }

       // Fonction pour réinstaller le Hub sur les appareils sélectionnés
       private func reinstallHubOnSelectedDevices() {
           guard !selectedDevices.isEmpty else { return }
           
           let apiManager = APIManager()
           for udid in selectedDevices {
               apiManager.installHub(on: udid)
           }
       }
   }


   struct LoginPopupView: View {
       @Binding var login: String
       @Binding var password: String
       @Binding var apiKey: String
       @Binding var isAuthenticated: Bool
       
       var body: some View {
           VStack {
               Text("S'authentifier")
                   .font(.headline)
                   .padding()

               TextField("Login", text: $login)
                   .padding()
                   .textFieldStyle(RoundedBorderTextFieldStyle())

               SecureField("Password", text: $password)
                   .padding()
                   .textFieldStyle(RoundedBorderTextFieldStyle())

               TextField("API Key", text: $apiKey)
                   .padding()
                   .textFieldStyle(RoundedBorderTextFieldStyle())

               Button("Se connecter") {
                   if saveCredentials() {
                       self.isAuthenticated = true
                   }
               }
               .padding()
               .background(Color.blue)
               .foregroundColor(.white)
               .cornerRadius(10)
           }
           .padding()
       }

       // Sauvegarde des informations dans le Keychain
       private func saveCredentials() -> Bool {
           guard !login.isEmpty, !password.isEmpty, !apiKey.isEmpty else {
               return false
           }
           
           return KeychainHelper.shared.savePassword(username: login, password: password, accountName: "WorkspaceOneCredentials")
       }
   }

   struct ContentView_Previews: PreviewProvider {
       static var previews: some View {
           ContentView()
       }
   }

class KeychainHelper {

    static let shared = KeychainHelper()

    // Clé pour identifier les données dans le Keychain
    private let service = "ch.epfl.ReinstallHub"
    
    // Fonction pour stocker un mot de passe dans le Keychain
    func savePassword(username: String, password: String, accountName: String) -> Bool {
        let loginPassword = "\(username):\(password)"
        let passwordData = loginPassword.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: passwordData
        ]
        
        // Effacer l'ancien mot de passe si il existe déjà
        SecItemDelete(query as CFDictionary)
        
        // Ajouter ou mettre à jour le mot de passe
        let status = SecItemAdd(query as CFDictionary, nil)
        
        return status == errSecSuccess
    }

    // Fonction pour récupérer un mot de passe à partir du Keychain
    func retrievePassword(for accountName: String) -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data,
           let loginPassword = String(data: data, encoding: .utf8)?.split(separator: ":") {
            let username = String(loginPassword[0])
            let password = String(loginPassword[1])
            return (username, password)
        } else {
            print("Erreur lors de la récupération du mot de passe ou compte non trouvé.")
            return nil
        }
    }

    // Fonction pour supprimer un mot de passe du Keychain
    func deletePassword(for accountName: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
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
