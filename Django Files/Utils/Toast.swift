//
//  Toast.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/29/25.
//

import SwiftUI

class ToastManager {
    static let shared = ToastManager()
    
    func showToast(message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        // Create a label for the toast
        let toastContainer = UIView()
        toastContainer.backgroundColor = UIColor.darkGray.withAlphaComponent(0.9)
        toastContainer.layer.cornerRadius = 16
        toastContainer.clipsToBounds = true
        
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        
//        // Create an image view for the clipboard icon
//        let imageView = UIImageView(image: UIImage(systemName: "doc.on.clipboard"))
//        imageView.tintColor = .white
//        imageView.contentMode = .scaleAspectFit
        
        // Create a stack view to hold the image and label
        let stackView = UIStackView(arrangedSubviews: [/*imageView,*/ messageLabel])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        
        // Add the stack view to the container
        toastContainer.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -12),
            stackView.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -16),
//            imageView.widthAnchor.constraint(equalToConstant: 20),
//            imageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Add the toast container to the window
        window.addSubview(toastContainer)
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Position the toast at the center bottom of the screen
        NSLayoutConstraint.activate([
            toastContainer.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toastContainer.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -64),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, multiplier: 0.85)
        ])
        
        // Animate the toast
        toastContainer.alpha = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            toastContainer.alpha = 1
        }) { _ in
            // Dismiss the toast after a delay
            UIView.animate(withDuration: 0.2, delay: 2.0, options: .curveEaseOut, animations: {
                toastContainer.alpha = 0
            }) { _ in
                toastContainer.removeFromSuperview()
            }
        }
    }
}
