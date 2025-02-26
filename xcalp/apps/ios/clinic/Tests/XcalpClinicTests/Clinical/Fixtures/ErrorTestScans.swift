import Foundation

struct ErrorTestScans {
    static func generateCorruptedScan() -> Data {
        // Generate intentionally corrupted OBJ data
        let corruptedOBJ = """
        v 1.0 2.0   // Missing Z coordinate
        v 2.0 3.0 4.0
        v abc def ghi  // Invalid coordinates
        f 1 2 3
        """
        return corruptedOBJ.data(using: .utf8)!
    }
    
    static func generateInvalidFormatScan() -> Data {
        // Generate data that's not in OBJ format
        let invalidFormat = """
        {
            "type": "mesh",
            "vertices": [[1,2,3], [4,5,6]],
            "faces": [[0,1,2]]
        }
        """
        return invalidFormat.data(using: .utf8)!
    }
    
    static func generateIncompleteDataScan() -> Data {
        // Generate incomplete OBJ data
        let incompleteOBJ = """
        v 1.0 2.0 3.0
        v 2.0 3.0 4.0
        // Missing faces and normals
        """
        return incompleteOBJ.data(using: .utf8)!
    }
    
    static func generateLargeInvalidScan() -> Data {
        // Generate a large file with invalid data
        var largeInvalidData = "v 1.0 2.0 3.0\n"
        for _ in 0..<10000 {
            largeInvalidData += "invalid_line\n"
        }
        return largeInvalidData.data(using: .utf8)!
    }
    
    static func generateMalformedScan() -> Data {
        // Generate OBJ with malformed face indices
        let malformedOBJ = """
        v 1.0 2.0 3.0
        v 2.0 3.0 4.0
        v 3.0 4.0 5.0
        f 1 2 4  // Invalid index
        f 2 3 1
        """
        return malformedOBJ.data(using: .utf8)!
    }
    
    static func generateEmptyScan() -> Data {
        return Data()
    }
}