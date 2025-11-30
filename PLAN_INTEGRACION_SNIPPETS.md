# 📋 Plan de Integración: Snippets con Timestamps para Chapters

## 🎯 Objetivo
Conectar los `snippets` con timestamps reales del backend (`app.py`) con el resto de la aplicación Swift, preparando para la funcionalidad de chapters, sin romper el flujo actual.

---

## 🔄 Flujo Actual vs Nuevo

### **Flujo ACTUAL** (sin cambios):
```
Backend (app.py)
  ↓ devuelve: {"text": "...", "language": {...}, "tracks": []}
  ↓
APIManager.fetchTranscript()
  ↓ devuelve: String (solo texto)
  ↓
MainViewModel.rawTranscript = String
  ↓
CacheManager.saveTranscript(String)
  ↓
Usado para: análisis, QA, etc.
```

### **Flujo NUEVO** (aditivo):
```
Backend (app.py)
  ↓ devuelve: {"text": "...", "snippets": [...], "language": {...}, "tracks": []}
  ↓
APIManager.fetchTranscript() + fetchTranscriptSnippets()
  ↓ devuelve: String + [TranscriptSnippet]? (opcional)
  ↓
MainViewModel.rawTranscript = String
MainViewModel.transcriptSnippets = [TranscriptSnippet]? (NUEVO)
  ↓
CacheManager.saveTranscript(String) + saveTranscriptSnippets([TranscriptSnippet]?)
  ↓
Usado para: análisis (igual), QA (igual), Chapters (NUEVO)
```

---

## 📝 Cambios Necesarios (Paso a Paso)

### **FASE 1: Modelos de Datos** ✅ Seguro

#### 1.1 Crear `TranscriptSnippet` en `Models.swift`
```swift
// Agregar después de BackendTranscriptResponse
struct TranscriptSnippet: Codable, Identifiable, Equatable {
    let id = UUID()
    let text: String
    let start: Double      // Tiempo en segundos
    let duration: Double   // Duración en segundos
    
    enum CodingKeys: String, CodingKey {
        case text, start, duration
    }
    
    // Computed property para convertir a segundos enteros
    var startSeconds: Int {
        Int(start.rounded())
    }
}
```

#### 1.2 Actualizar `BackendTranscriptResponse` en `Models.swift`
```swift
struct BackendTranscriptResponse: Codable {
    let video_id: String?
    let text: String?
    let snippets: [TranscriptSnippet]?  // ← NUEVO, opcional
    
    // JSONDecoder ignora campos que no están en el struct
    // Si el backend no envía snippets, será nil automáticamente
}
```

**✅ Seguridad**: Campo opcional, no rompe código existente

---

### **FASE 2: APIManager** ✅ Seguro

#### 2.1 Agregar método opcional para snippets en `APIManager.swift`
```swift
// Agregar después de fetchTranscript()
func fetchTranscriptSnippets(videoId: String) async throws -> [TranscriptSnippet]? {
    // Usar el mismo endpoint, pero decodificar snippets
    let response: BackendTranscriptResponse = try await performRequest(
        endpoint: "transcript",
        queryParams: ["videoId": videoId],
        timeout: 25
    )
    return response.snippets  // Puede ser nil si no hay snippets
}
```

**✅ Seguridad**: Método nuevo, no afecta `fetchTranscript()` existente

#### 2.2 Opcional: Modificar `fetchTranscript()` para también obtener snippets
```swift
// OPCIONAL: Modificar fetchTranscript() para devolver ambos
// PERO esto podría romper código existente, así que mejor NO hacerlo
// En su lugar, crear método separado o struct de retorno
```

**⚠️ Decisión**: NO modificar `fetchTranscript()` - mantener separado

---

### **FASE 3: CacheManager** ✅ Seguro

#### 3.1 Agregar métodos para snippets en `CacheManager.swift`
```swift
// Agregar después de loadTranscript()
func saveTranscriptSnippets(_ snippets: [TranscriptSnippet], for videoId: String) {
    saveDataToCache(snippets, forKey: "transcriptSnippets_\(videoId)")
}

func loadTranscriptSnippets(for videoId: String) -> [TranscriptSnippet]? {
    loadDataFromCache(forKey: "transcriptSnippets_\(videoId)", type: [TranscriptSnippet].self)
}
```

**✅ Seguridad**: Métodos nuevos, no afectan métodos existentes

---

### **FASE 4: MainViewModel** ✅ Seguro

#### 4.1 Agregar propiedad para snippets en `MainViewModel.swift`
```swift
// Agregar después de rawTranscript
@Published var transcriptSnippets: [TranscriptSnippet]? = nil
```

#### 4.2 Modificar `fetchTranscript()` en `MainViewModel.swift`
```swift
private func fetchTranscript(videoId: String) async throws -> String {
    let cache = cacheManager
    
    // Cargar transcript (como siempre)
    if let cachedTranscript = await cache.loadTranscript(for: videoId) {
        Logger.shared.info("Transcript cache HIT for \(videoId)", category: .cache)
        
        // NUEVO: También cargar snippets si existen
        if let cachedSnippets = await cache.loadTranscriptSnippets(for: videoId) {
            await MainActor.run {
                self.transcriptSnippets = cachedSnippets
            }
        }
        
        return cachedTranscript
    }
    
    // Fetch desde API
    Logger.shared.info("Fetching transcript from API for \(videoId)", category: .networking)
    let transcript = try await apiManager.fetchTranscript(videoId: videoId)
    
    // NUEVO: También obtener snippets
    if let snippets = try? await apiManager.fetchTranscriptSnippets(videoId: videoId) {
        await cache.saveTranscriptSnippets(snippets, for: videoId)
        await MainActor.run {
            self.transcriptSnippets = snippets
        }
    }
    
    await cache.saveTranscript(transcript, for: videoId)
    return transcript
}
```

**✅ Seguridad**: Cambios aditivos, el flujo actual sigue funcionando igual

---

### **FASE 5: Preparación para Chapters** 🔮 Futuro

#### 5.1 Crear modelo `VideoChapter` (cuando implementemos chapters)
```swift
struct VideoChapter: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let startSeconds: Int
    let description: String?
    
    // Se generará desde snippets + AI analysis
}
```

#### 5.2 Agregar propiedad en `MainViewModel`
```swift
@Published var chapters: [VideoChapter]? = nil
```

---

## 🛡️ Garantías de Seguridad

### ✅ **Backward Compatibility**
- Todos los campos nuevos son **opcionales**
- El código existente sigue funcionando igual
- Si no hay snippets, simplemente es `nil`

### ✅ **No Breaking Changes**
- `fetchTranscript()` sigue devolviendo `String`
- `rawTranscript` sigue siendo `String`
- Cache de transcript sigue funcionando igual

### ✅ **Progressive Enhancement**
- Los snippets se agregan gradualmente
- Si fallan, no rompen el flujo principal
- Cada fase es independiente

---

## 📊 Orden de Implementación Recomendado

1. ✅ **FASE 1**: Modelos (`TranscriptSnippet`, actualizar `BackendTranscriptResponse`)
2. ✅ **FASE 2**: APIManager (método `fetchTranscriptSnippets()`)
3. ✅ **FASE 3**: CacheManager (guardar/cargar snippets)
4. ✅ **FASE 4**: MainViewModel (almacenar snippets)
5. 🔮 **FASE 5**: UI para chapters (futuro)

---

## 🧪 Testing Strategy

### Test 1: Backward Compatibility
- Verificar que `fetchTranscript()` sigue funcionando
- Verificar que si no hay snippets, no rompe nada

### Test 2: Nuevo Flujo
- Verificar que snippets se obtienen cuando están disponibles
- Verificar que se guardan en cache correctamente
- Verificar que se cargan desde cache

### Test 3: Edge Cases
- Video sin snippets (fallback de yt-dlp)
- Cache sin snippets (videos antiguos)
- Snippets malformados

---

## 🎯 Resultado Final

Después de la integración:

```swift
// En MainViewModel, tendremos disponible:
viewModel.rawTranscript          // String (como siempre)
viewModel.transcriptSnippets      // [TranscriptSnippet]? (NUEVO)

// Para usar en chapters:
if let snippets = viewModel.transcriptSnippets {
    // Crear chapters desde snippets + AI analysis
    // Mostrar en UI
}
```

---

## ⚠️ Consideraciones Importantes

1. **No modificar `fetchTranscript()`**: Mantener separado para no romper código existente
2. **Snippets opcionales**: Siempre usar `?` y verificar con `if let`
3. **Cache separado**: Guardar snippets en cache separado del texto
4. **Error handling**: Si falla obtener snippets, no debe romper el transcript
5. **Performance**: Snippets son pequeños, no afectan performance

---

## 🚀 Próximos Pasos

Una vez implementado esto, podremos:
1. Usar snippets para generar chapters con AI
2. Mostrar chapters en la UI
3. Permitir saltar a momentos específicos del video
4. Mejorar la experiencia de usuario con navegación por chapters


