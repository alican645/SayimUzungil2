import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = InventoryCountViewModel()

    var body: some View {
        TabView {
            ScanScreen(viewModel: viewModel)
                .tabItem {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }

            StockListScreen(viewModel: viewModel)
                .tabItem {
                    Label("Stok List", systemImage: "shippingbox")
                }
        }
        .task {
            await viewModel.loadDepots()
        }
        .alert("Bilgi", isPresented: $viewModel.showAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}

private struct ScanScreen: View {
    @ObservedObject var viewModel: InventoryCountViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    depotSelectionCard
                    barcodeCard

                    if let product = viewModel.currentProduct {
                        productDetailCard(product)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Barkod Sayım")
        }
        .sheet(isPresented: $viewModel.isScannerPresented) {
            BarcodeScannerView { code in
                viewModel.barcodeInput = code
                Task { await viewModel.fetchProduct() }
            }
        }
    }

    private var depotSelectionCard: some View {
        card(title: "Depo") {
            if viewModel.isLoadingDepots {
                ProgressView("Depolar yükleniyor...")
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    private var barcodeCard: some View {
        card(title: "Barkod") {
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

    private func productDetailCard(_ product: Product) -> some View {
        card(title: "Ürün Bilgileri") {
            Group {
                infoRow(title: "Barkod", value: product.barcode)
                infoRow(title: "Malın Cinsi", value: product.malInCinsi)
                infoRow(title: "Stok Kodu", value: product.stokKodu)
                infoRow(title: "Ana Birim", value: product.anaBirim)
                infoRow(title: "Depo", value: product.depo)
            }

            HStack {
                TextField("Miktar", text: $viewModel.countInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Button("Lokale Ekle") {
                    viewModel.addCurrentProductToLocalStore()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(title):")
                .fontWeight(.semibold)
            Text(value)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct StockListScreen: View {
    @ObservedObject var viewModel: InventoryCountViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if viewModel.groupedItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Kayıt Yok")
                            .font(.headline)
                        Text("Lokale eklenen sayım kalemleri burada görüntülenir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.groupedItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.stokAdi)
                                    .font(.headline)
                                Text("Stok: \(item.stokKodu)")
                                Text("Depo: \(item.depoAdi)")
                                Text("Miktar: \(item.miktar.formattedAmount)")
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: viewModel.removeGroupedItems)
                    }
                    .listStyle(.plain)
                }

                Button {
                    Task { await viewModel.sendToVega() }
                } label: {
                    HStack {
                        if viewModel.isSending {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Vegaya İşle")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.groupedItems.isEmpty || viewModel.isSending)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Stok Listesi")
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
    @Published var groupedItems: [GroupedCountItem] = []
    @Published var errorMessage: String?
    @Published var isLoadingDepots = false
    @Published var isScannerPresented = false
    @Published var isSending = false
    @Published var showAlert = false
    @Published var alertMessage = ""

    private let baseURL = "http://192.168.10.2:82/SayimAktarmaApi"
    private let storageKey = "sayim.grouped.items"

    init() {
        loadLocalItems()
    }

    func loadDepots() async {
        isLoadingDepots = true
        defer { isLoadingDepots = false }

        guard let url = URL(string: "\(baseURL)/Depo") else {
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

    func addCurrentProductToLocalStore() {
        guard let product = currentProduct else {
            errorMessage = "Önce bir ürün sorgulayın."
            return
        }

        guard let count = Double(countInput.replacingOccurrences(of: ",", with: ".")), count > 0 else {
            errorMessage = "Geçerli bir miktar giriniz."
            return
        }

        guard let depot = depots.first(where: { $0.depoKodu == selectedDepotCode }) else {
            errorMessage = "Geçerli depo seçiniz."
            return
        }

        if let index = groupedItems.firstIndex(where: {
            $0.stokKodu == product.stokKodu && $0.depoAdi == depot.depoAdi
        }) {
            groupedItems[index].miktar += count
        } else {
            groupedItems.append(
                GroupedCountItem(
                    stokKodu: product.stokKodu,
                    stokAdi: product.malInCinsi,
                    miktar: count,
                    depoAdi: depot.depoAdi,
                    aciklama: "Mobil sayım",
                    sayimTipi: "GENEL",
                    yil: Calendar.current.component(.year, from: .now),
                    ay: Calendar.current.component(.month, from: .now)
                )
            )
        }

        persistLocalItems()

        alertMessage = "Ürün lokale eklendi."
        showAlert = true

        currentProduct = nil
        barcodeInput = ""
        countInput = ""
        errorMessage = nil
    }

    func removeGroupedItems(at offsets: IndexSet) {
        groupedItems.remove(atOffsets: offsets)
        persistLocalItems()
    }

    func sendToVega() async {
        guard !groupedItems.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/SendToVega") else {
            errorMessage = "SendToVega URL'i geçersiz."
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(groupedItems)

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SimpleApiResponse.self, from: data)

            if response.success {
                groupedItems.removeAll()
                persistLocalItems()
                alertMessage = response.message ?? "Kayıtlar Vega'ya başarıyla aktarıldı."
                showAlert = true
            } else {
                errorMessage = response.message ?? "Vega aktarımı başarısız."
            }
        } catch {
            errorMessage = "Vega aktarımında hata: \(error.localizedDescription)"
        }
    }

    private func loadLocalItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([GroupedCountItem].self, from: data)
        else {
            groupedItems = []
            return
        }
        groupedItems = decoded
    }

    private func persistLocalItems() {
        guard let data = try? JSONEncoder().encode(groupedItems) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
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

struct GroupedCountItem: Codable, Identifiable {
    let id: UUID
    let stokKodu: String
    let stokAdi: String
    var miktar: Double
    let depoAdi: String
    let aciklama: String
    let sayimTipi: String
    let yil: Int
    let ay: Int

    init(
        id: UUID = UUID(),
        stokKodu: String,
        stokAdi: String,
        miktar: Double,
        depoAdi: String,
        aciklama: String,
        sayimTipi: String,
        yil: Int,
        ay: Int
    ) {
        self.id = id
        self.stokKodu = stokKodu
        self.stokAdi = stokAdi
        self.miktar = miktar
        self.depoAdi = depoAdi
        self.aciklama = aciklama
        self.sayimTipi = sayimTipi
        self.yil = yil
        self.ay = ay
    }

    enum CodingKeys: String, CodingKey {
        case id
        case stokKodu
        case stokAdi = "stokAdı"
        case miktar
        case depoAdi
        case aciklama
        case sayimTipi
        case yil
        case ay
    }
}

struct SimpleApiResponse: Decodable {
    let success: Bool
    let message: String?
}

private extension Double {
    var formattedAmount: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 0
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

#Preview {
    ContentView()
}
