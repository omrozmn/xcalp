extension TemplateVersionEntity {
    func toModel() throws -> TreatmentTemplate {
        let decoder = JSONDecoder()
        
        let parameters = try decoder.decode([TreatmentTemplate.Parameter].self, from: parametersData ?? Data())
        let regions = try decoder.decode([TreatmentRegion].self, from: regionsData ?? Data())
        
        return TreatmentTemplate(
            id: templateId ?? UUID(),
            name: name ?? "",
            description: templateDescription ?? "",
            version: Int(version),
            createdAt: createdAt ?? Date(),
            updatedAt: createdAt ?? Date(), // Use createdAt for versions
            parameters: parameters,
            regions: regions,
            author: author ?? "",
            isCustom: isCustom,
            parentTemplateId: parentTemplateId
        )
    }
}