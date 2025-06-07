//
//  Info.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/5/25.
//

import SwiftUI

struct PreviewFileInfo: View {
    let file: DFFile
    
    // Helper function to format EXIF date string
    private func formatExifDate(_ dateString: String) -> String {
        let exifFormatter = DateFormatter()
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        
        guard let date = exifFormatter.date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper function to convert decimal to fraction string
    private func formatExposureTime(_ exposure: String) -> String {
        if let value = Double(exposure) {
            if value >= 1 {
                return "\(Int(value))"
            } else {
                let denominator = Int(round(1.0 / value))
                return "1/\(denominator)"
            }
        }
        return exposure
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(file.name)")
                .font(.title)
            HStack {
                HStack {
                    Image(systemName: "document")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.teal)
                    Text("\(file.mime)")
                        .foregroundColor(.teal)
                }

                if file.password != "" {
                    Image(systemName: "key")
                        .frame(width: 20, height: 20)
                }
                if file.private {
                    Image(systemName: "lock")
                        .frame(width: 20, height: 20)
                }
                if file.expr != "" {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .frame(width: 20, height: 20)
                }
                if file.maxv != 0 {
                    HStack {
                        Image(systemName: "eye.circle")
                            .frame(width: 20, height: 20)
                        Text("Max Views: \(String(file.maxv))")
                    }
                }
                if let width = file.meta?["PILImageWidth"]?.value as? Int,
                   let height = file.meta?["PILImageHeight"]?.value as? Int {
                    Spacer()
                    Text("\(width)×\(height)")
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                HStack {
                    Image(systemName: "person")
                        .frame(width: 20, height: 20)
                    Text("\(file.userUsername)")
                }
                Spacer()
                HStack {
                    Image(systemName: "eye")
                        .frame(width: 20, height: 20)
                    Text("\(file.view)")
                }
                Spacer()
                HStack {
                    Image(systemName: "internaldrive")
                        .frame(width: 20, height: 20)
                    Text(file.formatSize())
                }
            }

            HStack {
                Image(systemName: "calendar")
                    .frame(width: 15, height: 15)
                Text("\(file.formattedDate())")
            }
            
            // Photo Information Section
            if let dateTime = file.exif?["DateTimeOriginal"]?.value as? String {
                HStack {
                    Image(systemName: "camera")
                        .frame(width: 15, height: 15)
                        .font(.caption)
                    Text("Captured: \(formatExifDate(dateTime))")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            if let gpsArea = file.meta?["GPSArea"]?.value as? String {
                HStack {
                    Image(systemName: "location")
                        .frame(width: 15, height: 15)
                    Text(gpsArea)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            if let elevation = file.exif?["GPSInfo"]?.value as? [String: Any],
               let altitude = elevation["6"] as? Double {
                HStack{
                    Image(systemName: "mountain.2.circle")
                        .frame(width: 15, height: 15)
                    Text(String(format: "Elevation: %.1f m", altitude))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            // Camera Information Section
            Group {
                if let model = file.exif?["Model"]?.value as? String {
                    let make = file.exif?["Make"]?.value as? String ?? ""
                    let cameraName = make.isEmpty || model.contains(make) ? model : "\(make) \(model)"
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 15, height: 15)
                        Text("Camera: \(cameraName)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let lens = file.exif?["LensModel"]?.value as? String {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 15, height: 15)
                        Text("Lens: \(lens)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                
                if let focalLength = file.exif?["FocalLength"]?.value as? Double {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 15, height: 15)
                        Text(String(format: "Focal Length: %.0fmm", focalLength))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let fNumber = file.exif?["FNumber"]?.value as? Double {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 15, height: 15)
                        Text(String(format: "Aperture: 𝑓%.1f", fNumber))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let iso = file.exif?["ISOSpeedRatings"]?.value as? Int {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text("ISO: \(iso)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                }
                
                if let exposureTime = file.exif?["ExposureTime"]?.value as? String {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 15, height: 15)
                        Text("Exposure: \(formatExposureTime(exposureTime))s")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let software = file.exif?["Software"]?.value as? String {
                    HStack {
                        Image(systemName: "app")
                            .frame(width: 15, height: 15)
                        Text("Software: \(software)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            if !file.info.isEmpty {
                Text(file.info)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
    }
}
