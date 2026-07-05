//
//  PasswordAutofillCoordinator+Structured.swift
//  evo
//
//  Fill logic shared by the credit-card (Task 3.1) and identity/address (Task 4.1)
//  overlay rows. Both categories flow through the same `fillStructured` path: fetch
//  secrets on demand via `PasswordProvider.fillValues(for:)`, then map the focused
//  field list to the values the provider returned, skipping any purpose it didn't have.
//

import AppKit
import Foundation

extension PasswordAutofillCoordinator {
    func fillStructured(_ item: ProviderStructuredItem, for overlay: PasswordAutofillOverlayState) {
        Task { [weak self] in
            guard let self else { return }

            let provider = await self.providers.activeProvider(for: self.settings.passwordManagerProvider)
            guard let values = try? await provider.fillValues(for: item.ref) else { return }

            await MainActor.run {
                let entries = Self.structuredFillEntries(fields: overlay.focus.fields ?? [], values: values)
                guard !entries.isEmpty else { return }

                let request = PasswordMultiFillRequest(fields: entries, highlightColor: "#E8F5E9")
                self.evaluate(scriptMethod: "fillFields", payload: request)
                self.dismissOverlay()
            }
        }
    }

    /// Maps a structured item's focus fields to fill values, skipping any purpose the
    /// provider didn't return a value for. Pulled out of `fillStructured` so the mapping
    /// (missing purposes skipped, no empty/garbage values) is unit-testable without a `Tab`.
    static func structuredFillEntries(
        fields: [PasswordBridgeField],
        values: [FieldPurpose: String]
    ) -> [PasswordMultiFillRequest.FieldEntry] {
        fields.compactMap { field in
            guard let value = values[field.purpose] else { return nil }
            return PasswordMultiFillRequest.FieldEntry(fieldID: field.fieldID, value: value)
        }
    }
}
