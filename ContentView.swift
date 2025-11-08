import SwiftUI

// MARK: - Allowed Nodes
let allowedNodes = [
    "G01","G02","G03","G04","G05","G06","G07","G08","G08A","G08B",
    "G10","G10A","G11","G12","G13","G14","G16","G17","G18","G19",
    "Store 1","Store 2","Xerox Shop"
]

// MARK: - Data Models
struct MapData: Codable {
    let version: String
    let units: String
    let origin: [Double]
    let levels: [Level]

    struct Level: Codable {
        let level_id: String
        let rooms: [Room]
        let obstacles: [Obstacle]?
        let nodes: [Node]?

        struct Room: Codable, Identifiable {
            var id = UUID()
            let room_id: String
            let name: String
            let geometry: Geometry
            let doors: [Door]

            private enum CodingKeys: String, CodingKey {
                case room_id, name, geometry, doors
            }

            struct Geometry: Codable {
                let type: String
                let coordinates: [[[Double]]]
            }

            struct Door: Codable {
                let label: String
                let position: [Double]
            }
        }

        struct Obstacle: Codable, Identifiable {
            var id = UUID()
            let obstacle_id: String
            let geometry: Geometry

            private enum CodingKeys: String, CodingKey {
                case obstacle_id, geometry
            }

            struct Geometry: Codable {
                let type: String
                let coordinates: [[[Double]]]
            }
        }

        struct Node: Codable, Identifiable {
            var id = UUID()
            let label: String
            let position: [Double]

            private enum CodingKeys: String, CodingKey {
                case label, position
            }
        }
    }
}

// MARK: - ViewModel
final class MapViewModel: ObservableObject {
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var selectedRoomID: String? = nil
    @Published var sourceRoomID: String? = nil
    @Published var destinationRoomID: String? = nil
    @Published var sourceDoorLabel: String? = nil
    @Published var destinationDoorLabel: String? = nil
    @Published var path: [String] = [] // Path of node labels for A* visualization
}

// MARK: - Generate adjacency based on node proximity
private func generateAdjacency(nodes: [MapData.Level.Node], maxDistance: Double = 12) -> [String: [String]] {
    var adjacency: [String: [String]] = [:]
    
    for node in nodes {
        var neighbors: [String] = []
        for other in nodes {
            if node.label == other.label { continue }
            let dx = node.position[0] - other.position[0]
            let dy = node.position[1] - other.position[1]
            let distance = sqrt(dx*dx + dy*dy)
            if distance <= maxDistance {
                neighbors.append(other.label)
            }
        }
        adjacency[node.label] = neighbors
    }
    
    return adjacency
}


// MARK: - Floor Plan View
struct FloorPlanView: View {
    let level: MapData.Level
    @ObservedObject var vm: MapViewModel

    var body: some View {
        GeometryReader { geo in
            let allX = level.rooms.flatMap { $0.geometry.coordinates.first ?? [] }.map { $0[0] }
            let allY = level.rooms.flatMap { $0.geometry.coordinates.first ?? [] }.map { $0[1] }
            let minX = allX.min() ?? 0, maxX = allX.max() ?? 1
            let minY = allY.min() ?? 0, maxY = allY.max() ?? 1
            let scaleX = geo.size.width / CGFloat(maxX - minX)
            let scaleY = geo.size.height / CGFloat(maxY - minY)

            ZStack {
                Color.white.ignoresSafeArea()

                // Rooms
                ForEach(level.rooms) { room in
                    if let coords = room.geometry.coordinates.first {
                        let xs = coords.map { $0[0] }
                        let ys = coords.map { $0[1] }
                        let rMinX = xs.min() ?? 0
                        let rMaxX = xs.max() ?? 0
                        let rMinY = ys.min() ?? 0
                        let rMaxY = ys.max() ?? 0
                        let center = CGPoint(
                            x: CGFloat(rMinX + (rMaxX - rMinX)/2 - minX) * scaleX,
                            y: geo.size.height - CGFloat(rMinY + (rMaxY - rMinY)/2 - minY) * scaleY
                        )

                        let isSource = vm.sourceRoomID == room.room_id
                        let isDestination = vm.destinationRoomID == room.room_id
                        let roomColor: Color = (isSource || isDestination)
                            ? Color.blue.opacity(0.4)
                            : Color.purple.opacity(0.7)

                        Rectangle()
                            .fill(roomColor)
                            .frame(width: CGFloat(rMaxX - rMinX) * scaleX, height: CGFloat(rMaxY - rMinY) * scaleY)
                            .position(center)
                            .onTapGesture {
                                vm.selectedRoomID = room.room_id
                            }

                        Text(room.name)
                            .font(.caption)
                            .foregroundColor(.black)
                            .position(center)
                    }

                    // Doors
                    ForEach(room.doors, id: \.label) { door in
                        let isSourceDoor = vm.sourceDoorLabel == door.label
                        let isDestinationDoor = vm.destinationDoorLabel == door.label

                        Circle()
                            .fill(isSourceDoor ? Color.green : (isDestinationDoor ? Color.red : Color.blue))
                            .frame(width: 12, height: 12)
                            .position(
                                x: CGFloat((door.position.first ?? 0) - minX) * scaleX,
                                y: geo.size.height - CGFloat((door.position.last ?? 0) - minY) * scaleY
                            )
                    }
                }

                // Obstacles
                if let obstacles = level.obstacles {
                    ForEach(obstacles) { obs in
                        if let coords = obs.geometry.coordinates.first {
                            let xVals = coords.map { $0[0] }
                            let yVals = coords.map { $0[1] }
                            let oMinX = xVals.min() ?? 0
                            let oMaxX = xVals.max() ?? 0
                            let oMinY = yVals.min() ?? 0
                            let oMaxY = yVals.max() ?? 0

                            Rectangle()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: CGFloat(oMaxX - oMinX) * scaleX, height: CGFloat(oMaxY - oMinY) * scaleY)
                                .position(
                                    x: CGFloat(oMinX + (oMaxX - oMinX)/2 - minX) * scaleX,
                                    y: geo.size.height - CGFloat(oMinY + (oMaxY - oMinY)/2 - minY) * scaleY
                                )
                        }
                    }
                }

                // Nodes with path highlighting
                if let nodes = level.nodes, vm.path.count > 1 {
                    Path { path in
                        for i in 0..<(vm.path.count - 1) {
                            if let startNode = nodes.first(where: { $0.label == vm.path[i] }),
                               let endNode = nodes.first(where: { $0.label == vm.path[i+1] }) {

                                let startX = CGFloat(startNode.position[0] - minX) * scaleX
                                let startY = geo.size.height - CGFloat(startNode.position[1] - minY) * scaleY
                                let endX = CGFloat(endNode.position[0] - minX) * scaleX
                                let endY = geo.size.height - CGFloat(endNode.position[1] - minY) * scaleY

                                if i == 0 {
                                    path.move(to: CGPoint(x: startX, y: startY))
                                }
                                path.addLine(to: CGPoint(x: endX, y: endY))
                            }
                        }
                    }
                    .stroke(Color.orange, lineWidth: 3)
                }
            }
            .scaleEffect(vm.scale)
            .offset(vm.offset)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture().onChanged { vm.scale = $0 },
                    DragGesture().onChanged { vm.offset = $0.translation }
                )
            )
        }
    }
}

// MARK: - Main Content
struct ContentView: View {
    @StateObject private var vm = MapViewModel()
    @State private var mapData: MapData?
    @State private var level: MapData.Level?
    @State private var showPopup = false
    @State private var currentLocation = allowedNodes.first ?? ""
    @State private var destination = allowedNodes.last ?? ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var invalidSource = false
    @State private var invalidDestination = false

    var body: some View {
        ZStack(alignment: .top) {
            if let lvl = level {
                FloorPlanView(level: lvl, vm: vm)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.white.ignoresSafeArea()
                Text("Loading map…")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Header
            HStack {
                Text("Navigation Made Easier")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                Button(action: { showPopup.toggle() }) {
                    Image(systemName: "map.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                        .padding(.trailing, 12)
                }
            }
            .padding()
            .background(Color.white.opacity(0.95))
            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
            .zIndex(1)
        }
        .onAppear(perform: loadJSON)
        .sheet(isPresented: $showPopup) {
            NavigationView {
                Form {
                    Section(header: Text("Current Location")) {
                        Picker("Select source", selection: $currentLocation) {
                            ForEach(allowedNodes, id: \.self) { node in
                                Text(node)
                            }
                        }
                    }

                    Section(header: Text("Destination")) {
                        Picker("Select destination", selection: $destination) {
                            ForEach(allowedNodes, id: \.self) { node in
                                Text(node)
                            }
                        }
                    }

                    Section {
                        Button(action: handleNavigation) {
                            Text("Take Me There")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                }
                .navigationTitle("Select Locations")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Error", isPresented: $showAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(alertMessage)
        })
    }

    // MARK: - JSON Loading
    private func loadJSON() {
        guard let url = Bundle.main.url(forResource: "room_new", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ JSON file not found in bundle")
            return
        }

        do {
            let decoded = try JSONDecoder().decode(MapData.self, from: data)
            mapData = decoded
            level = decoded.levels.first
            print("✅ Decoded map successfully")
        } catch {
            print("❌ Decoding failed:", error)
        }
    }

    // MARK: - Handle Navigation + A* Pathfinding
    private func handleNavigation() {
        guard let lvl = level else { return }

        vm.sourceRoomID = nil
        vm.destinationRoomID = nil
        vm.sourceDoorLabel = nil
        vm.destinationDoorLabel = nil
        vm.path = []
        invalidSource = false
        invalidDestination = false

        var sourceFound = false
        var destFound = false

        for room in lvl.rooms {
            if room.name == currentLocation || room.room_id == currentLocation {
                vm.sourceRoomID = room.room_id
                sourceFound = true
            }
            if room.name == destination || room.room_id == destination {
                vm.destinationRoomID = room.room_id
                destFound = true
            }
            for door in room.doors {
                if door.label == currentLocation {
                    vm.sourceDoorLabel = door.label
                    sourceFound = true
                }
                if door.label == destination {
                    vm.destinationDoorLabel = door.label
                    destFound = true
                }
            }
        }

        invalidSource = !sourceFound
        invalidDestination = !destFound

        if !sourceFound || !destFound {
            alertMessage = "Incorrect location or destination selected."
            showAlert = true
        } else {
            // A* Pathfinding
            if let src = vm.sourceDoorLabel ?? vm.sourceRoomID,
               let dst = vm.destinationDoorLabel ?? vm.destinationRoomID,
               let nodes = lvl.nodes {
                vm.path = aStarPath(from: src, to: dst, nodes: nodes)
            }
            showPopup = false
        }
    }

    private func aStarPath(from startLabel: String, to endLabel: String, nodes: [MapData.Level.Node]) -> [String] {
        var openSet = Set([startLabel])
        var cameFrom: [String: String] = [:]
        var gScore: [String: Double] = nodes.reduce(into: [:]) { $0[$1.label] = Double.infinity }
        gScore[startLabel] = 0

        func heuristic(_ a: MapData.Level.Node, _ b: MapData.Level.Node) -> Double {
            let dx = a.position[0] - b.position[0]
            let dy = a.position[1] - b.position[1]
            return sqrt(dx*dx + dy*dy)
        }

        let adjacency = generateAdjacency(nodes: nodes)

        func neighbors(_ label: String) -> [MapData.Level.Node] {
            guard let neighborLabels = adjacency[label] else { return [] }
            return nodes.filter { neighborLabels.contains($0.label) }
        }


        while !openSet.isEmpty {
            let current = openSet.min { gScore[$0, default: Double.infinity] < gScore[$1, default: Double.infinity] }!
            if current == endLabel { break }
            openSet.remove(current)
            guard let currentNode = nodes.first(where: { $0.label == current }) else { continue }
            for neighbor in neighbors(current) {
                let tentativeG = gScore[current]! + heuristic(currentNode, neighbor)
                if tentativeG < gScore[neighbor.label, default: Double.infinity] {
                    cameFrom[neighbor.label] = current
                    gScore[neighbor.label] = tentativeG
                    openSet.insert(neighbor.label)
                }
            }
        }

        var path: [String] = []
        var current: String? = endLabel
        while let c = current {
            path.append(c)
            current = cameFrom[c]
        }
        return path.reversed()
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
