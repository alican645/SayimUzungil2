import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = InventoryCountViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                depotSelectionSection
                barcodeSection

                if let product = viewModel.currentProduct {
                    productDetailSection(product)
                }

                countListSection
            }
            .padding()
            .navigationTitle("Sayım Aktarma")
            .task {
                await viewModel.loadDepots()
            }
            .alert("Bilgi", isPresented: $viewModel.showSaveAlert) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.saveAlertMessage)
            }
        }
        .sheet(isPresented: $viewModel.isScannerPresented) {
            BarcodeScannerView { code in
                viewModel.barcodeInput = code
                Task { await viewModel.fetchProduct() }
            }
        }
    }

    private var depotSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depo Seçimi")
                .font(.headline)

            if viewModel.isLoadingDepots {
                ProgressView("Depolar yükleniyor...")
            } else {
                Picker("Depo", selection: $viewModel.selectedDepotCode) {
                    Text("Depo seçiniz").tag("")
                    ForEach(viewModel.depots) { depot in
                        Text("\(depot.depoAdi) (\(depot.depoKodu))")
                            .tag(depot.depoKodu)
                    }
                }
                .pickerStyle(.menu)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var barcodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Barkod")
                .font(.headline)

            HStack {
                TextField("Barkod girin", text: $viewModel.barcodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Sorgula") {
                    Task { await viewModel.fetchProduct() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                viewModel.isScannerPresented = true
            } label: {
                Label("Kamerayı Aç", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func productDetailSection(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ürün Bilgileri")
                .font(.headline)

            Group {
                infoRow(title: "Barkod", value: product.barcode)
                infoRow(title: "Malın Cinsi", value: product.malInCinsi)
                infoRow(title: "Stok Kodu", value: product.stokKodu)
                infoRow(title: "Ana Birim", value: product.anaBirim)
                infoRow(title: "Depo", value: product.depo)
                infoRow(title: "Kod1", value: product.kod1)
                infoRow(title: "Kod2", value: product.kod2)
                infoRow(title: "Kod3", value: product.kod3)
            }

            HStack {
                TextField("Sayım adeti", text: $viewModel.countInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Button("Listeye Ekle") {
                    viewModel.addCurrentProductToList()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var countListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sayım Listesi")
                    .font(.headline)
                Spacer()
                Text("Toplam: \(viewModel.countItems.count)")
                    .foregroundStyle(.secondary)
            }

            if viewModel.countItems.isEmpty {
                Text("Henüz ürün eklenmedi.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(viewModel.countItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.product.malInCinsi) - \(item.product.stokKodu)")
                                .font(.headline)
                            Text("Barkod: \(item.product.barcode)")
                            Text("Depo: \(item.selectedDepotCode)")
                            Text("Adet: \(item.count)")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: viewModel.removeItems)
                }
                .frame(minHeight: 220)

                Button {
                    viewModel.saveAll()
                } label: {
                    Text("Hepsini Kaydet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title + ":")
                .fontWeight(.semibold)
            Text(value)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

@MainActor
final class InventoryCountViewModel: ObservableObject {
    @Published var depots: [Depot] = []
    @Published var selectedDepotCode: String = ""
    @Published var barcodeInput: String = ""
    @Published var countInput: String = ""
    @Published var currentProduct: Product?
    @Published var countItems: [CountItem] = []
    @Published var errorMessage: String?
    @Published var isLoadingDepots = false
    @Published var isScannerPresented = false
    @Published var showSaveAlert = false
    @Published var saveAlertMessage = ""

    private let baseURL = "http://192.168.10.2:82/SayimAktarmaApi"

    func loadDepots() async {
        isLoadingDepots = true
        defer { isLoadingDepots = false }

        guard let encoded = "\(baseURL)/Depo".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded)
        else {
            errorMessage = "Depo URL'i geçersiz."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(DepotResponse.self, from: data)
            guard response.success else {
                errorMessage = "Depo bilgileri alınamadı."
                return
            }
            depots = response.data
            if selectedDepotCode.isEmpty {
                selectedDepotCode = depots.first?.depoKodu ?? ""
            }
            errorMessage = nil
        } catch {
            errorMessage = "Depolar yüklenirken hata oluştu: \(error.localizedDescription)"
        }
    }

    func fetchProduct() async {
        let barcode = barcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else { return }
        guard !selectedDepotCode.isEmpty else {
            errorMessage = "Önce depo seçiniz."
            return
        }

        var components = URLComponents(string: baseURL)
        components?.queryItems = [URLQueryItem(name: "barcode", value: barcode)]

        guard let url = components?.url else {
            errorMessage = "Barkod URL'i geçersiz."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ProductResponse.self, from: data)
            guard response.success else {
                errorMessage = "Ürün bulunamadı."
                return
            }
            currentProduct = response.data
            countInput = ""
            errorMessage = nil
            isScannerPresented = false
        } catch {
            errorMessage = "Ürün sorgulanırken hata oluştu: \(error.localizedDescription)"
        }
    }

    func addCurrentProductToList() {
        guard let product = currentProduct else {
            errorMessage = "Önce bir ürün sorgulayın."
            return
        }
        guard !selectedDepotCode.isEmpty else {
            errorMessage = "Depo seçimi zorunludur."
            return
        }
        guard let count = Double(countInput.replacingOccurrences(of: ",", with: ".")), count > 0 else {
            errorMessage = "Geçerli bir sayım adeti giriniz."
            return
        }

        countItems.append(
            CountItem(product: product, selectedDepotCode: selectedDepotCode, count: count)
        )

        currentProduct = nil
        barcodeInput = ""
        countInput = ""
        errorMessage = nil
    }

    func removeItems(at offsets: IndexSet) {
        countItems.remove(atOffsets: offsets)
    }

    func saveAll() {
        guard !countItems.isEmpty else { return }
        let totalItems = countItems.count
        countItems.removeAll()
        saveAlertMessage = "\(totalItems) kalem sayım listesi kaydedildi (lokal)."
        showSaveAlert = true
    }
}

struct Depot: Decodable, Identifiable {
    let ind: Int
    let depoAdi: String
    let depoKodu: String

    var id: Int { ind }

    enum CodingKeys: String, CodingKey {
        case ind = "Ind"
        case depoAdi = "DepoAdi"
        case depoKodu = "DepoKodu"
    }
}

struct DepotResponse: Decodable {
    let success: Bool
    let data: [Depot]
}

struct Product: Decodable {
    let barcode: String
    let ind: Int
    let malInCinsi: String
    let stokKodu: String
    let anaBirim: String
    let depo: String
    let kod1: String
    let kod2: String
    let kod3: String
    let dalisFiyati: Double

    enum CodingKeys: String, CodingKey {
        case barcode = "Barcode"
        case ind = "Ind"
        case malInCinsi = "MalInCinsi"
        case stokKodu = "StokKodu"
        case anaBirim = "AnaBirim"
        case depo = "Depo"
        case kod1 = "Kod1"
        case kod2 = "Kod2"
        case kod3 = "Kod3"
        case dalisFiyati = "DalisFiyati"
    }
}

struct ProductResponse: Decodable {
    let success: Bool
    let data: Product
}

struct CountItem: Identifiable {
    let id = UUID()
    let product: Product
    let selectedDepotCode: String
    let count: Double
}

#Preview {
    ContentView()
}
