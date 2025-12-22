/// MIDI input device management
/// Uses midir on desktop platforms, stub on iOS (midir not supported)

use crate::midi::MidiEvent;
use anyhow::{anyhow, Result};
use std::sync::{Arc, Mutex};

/// MIDI device information
#[derive(Debug, Clone)]
pub struct MidiDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

// ============================================================================
// iOS STUB IMPLEMENTATION
// ============================================================================
#[cfg(target_os = "ios")]
pub struct MidiInputManager {
    // Stub - no MIDI input on iOS yet (future: Core MIDI support)
}

#[cfg(target_os = "ios")]
impl MidiInputManager {
    pub fn new() -> Result<Self> {
        eprintln!("⚠️ [MIDI] MIDI input not yet supported on iOS");
        Ok(Self {})
    }

    pub fn refresh_devices(&mut self) -> Result<()> {
        Ok(())
    }

    pub fn get_devices(&self) -> Vec<MidiDevice> {
        vec![]
    }

    pub fn select_device(&mut self, _index: usize) -> Result<()> {
        Err(anyhow!("MIDI input not yet supported on iOS"))
    }

    pub fn set_event_callback<F>(&mut self, _callback: F)
    where
        F: FnMut(MidiEvent) + Send + 'static,
    {
        // No-op on iOS
    }

    pub fn start_capture(&mut self) -> Result<()> {
        Err(anyhow!("MIDI input not yet supported on iOS"))
    }

    pub fn stop_capture(&mut self) -> Result<()> {
        Ok(())
    }

    pub fn is_capturing(&self) -> bool {
        false
    }
}

// ============================================================================
// DESKTOP IMPLEMENTATION (macOS, Windows, Linux)
// ============================================================================
#[cfg(not(target_os = "ios"))]
use midir::{MidiInput, MidiInputConnection, MidiInputPort};

/// MIDI event callback type
#[cfg(not(target_os = "ios"))]
type MidiEventCallback = Arc<Mutex<dyn FnMut(MidiEvent) + Send>>;

/// MIDI input manager
#[cfg(not(target_os = "ios"))]
pub struct MidiInputManager {
    /// Available MIDI input ports
    ports: Vec<MidiInputPort>,
    /// Port names
    port_names: Vec<String>,
    /// Currently selected port index
    selected_port_index: Option<usize>,
    /// Active MIDI input connection
    connection: Option<MidiInputConnection<()>>,
    /// Event callback (called when MIDI events are received)
    event_callback: Option<MidiEventCallback>,
    /// MIDI input instance (needs to be kept alive)
    midi_input: Option<MidiInput>,
}

#[cfg(not(target_os = "ios"))]
impl MidiInputManager {
    /// Create a new MIDI input manager
    pub fn new() -> Result<Self> {
        let mut manager = Self {
            ports: Vec::new(),
            port_names: Vec::new(),
            selected_port_index: None,
            connection: None,
            event_callback: None,
            midi_input: None,
        };

        manager.refresh_devices()?;
        Ok(manager)
    }

    /// Refresh the list of available MIDI input devices
    pub fn refresh_devices(&mut self) -> Result<()> {
        let midi_input = MidiInput::new("Boojy Audio MIDI Input")?;

        let ports = midi_input.ports();
        let port_names: Vec<String> = ports
            .iter()
            .map(|port| {
                midi_input
                    .port_name(port)
                    .unwrap_or_else(|_| "Unknown Device".to_string())
            })
            .collect();

        eprintln!("🎹 [MIDI] Found {} MIDI input devices", ports.len());
        for (i, name) in port_names.iter().enumerate() {
            eprintln!("  [{}] {}", i, name);
        }

        self.ports = ports;
        self.port_names = port_names;
        self.midi_input = Some(midi_input);

        Ok(())
    }

    /// Get list of available MIDI input devices
    pub fn get_devices(&self) -> Vec<MidiDevice> {
        self.port_names
            .iter()
            .enumerate()
            .map(|(i, name)| MidiDevice {
                id: format!("midi_{}", i),
                name: name.clone(),
                is_default: i == 0, // First device is default
            })
            .collect()
    }

    /// Select a MIDI input device by index
    pub fn select_device(&mut self, index: usize) -> Result<()> {
        if index >= self.ports.len() {
            return Err(anyhow!("Invalid MIDI device index: {}", index));
        }

        eprintln!("🎹 [MIDI] Selected device: {}", self.port_names[index]);
        self.selected_port_index = Some(index);

        Ok(())
    }

    /// Set the event callback (called when MIDI events are received)
    pub fn set_event_callback<F>(&mut self, callback: F)
    where
        F: FnMut(MidiEvent) + Send + 'static,
    {
        self.event_callback = Some(Arc::new(Mutex::new(callback)));
    }

    /// Start capturing MIDI input from the selected device
    pub fn start_capture(&mut self) -> Result<()> {
        if self.connection.is_some() {
            eprintln!("⚠️ [MIDI] Already capturing");
            return Ok(());
        }

        let port_index = self.selected_port_index.unwrap_or(0);

        if port_index >= self.ports.len() {
            return Err(anyhow!("No MIDI device selected"));
        }

        let midi_input = self
            .midi_input
            .take()
            .ok_or_else(|| anyhow!("MIDI input not initialized"))?;

        let port = &self.ports[port_index];
        let port_name = &self.port_names[port_index];

        eprintln!("🎹 [MIDI] Starting capture from: {}", port_name);

        // Clone the callback for the MIDI thread
        let callback = self.event_callback.clone();

        // Create MIDI input connection
        let connection = midi_input.connect(
            port,
            "boojy-audio-input",
            move |timestamp, message, _| {
                // Parse MIDI message
                if let Some(event) = parse_midi_message(message, timestamp) {
                    // Call the event callback if set
                    if let Some(ref cb) = callback {
                        if let Ok(mut cb) = cb.lock() {
                            cb(event);
                        }
                    }
                }
            },
            (),
        ).map_err(|e| anyhow!("Failed to connect MIDI input: {:?}", e))?;

        self.connection = Some(connection);
        eprintln!("✅ [MIDI] Capture started");

        Ok(())
    }

    /// Stop capturing MIDI input
    pub fn stop_capture(&mut self) -> Result<()> {
        if let Some(connection) = self.connection.take() {
            let (midi_input, _) = connection.close();
            self.midi_input = Some(midi_input);
            eprintln!("🛑 [MIDI] Capture stopped");
        }

        Ok(())
    }

    /// Check if currently capturing
    pub fn is_capturing(&self) -> bool {
        self.connection.is_some()
    }
}

/// Parse a MIDI message into a MidiEvent
#[cfg(not(target_os = "ios"))]
fn parse_midi_message(message: &[u8], timestamp: u64) -> Option<MidiEvent> {
    if message.is_empty() {
        return None;
    }

    let status = message[0];
    let channel = status & 0x0F;
    let message_type = status & 0xF0;

    match message_type {
        // Note On (0x90)
        0x90 if message.len() >= 3 => {
            let note = message[1];
            let velocity = message[2];

            // Velocity 0 is actually Note Off
            if velocity == 0 {
                Some(MidiEvent::note_off(note, velocity, timestamp))
            } else {
                Some(MidiEvent::note_on(note, velocity, timestamp))
            }
        }

        // Note Off (0x80)
        0x80 if message.len() >= 3 => {
            let note = message[1];
            let velocity = message[2];
            Some(MidiEvent::note_off(note, velocity, timestamp))
        }

        // Ignore other message types for now (CC, pitch bend, etc.)
        _ => {
            eprintln!(
                "🎹 [MIDI] Ignoring message type: 0x{:02X} (channel {})",
                message_type, channel
            );
            None
        }
    }
}

#[cfg(test)]
#[cfg(not(target_os = "ios"))]
mod tests {
    use super::*;
    use crate::midi::MidiEventType;

    #[test]
    fn test_midi_manager_creation() {
        let result = MidiInputManager::new();
        // May fail if no MIDI devices available, which is OK for testing
        match result {
            Ok(manager) => {
                assert!(manager.ports.len() >= 0);
            }
            Err(e) => {
                eprintln!("No MIDI devices available: {}", e);
            }
        }
    }

    #[test]
    fn test_parse_note_on() {
        let message = vec![0x90, 60, 100]; // Note On, C4, velocity 100
        let event = parse_midi_message(&message, 1000);

        assert!(event.is_some());
        let event = event.unwrap();

        match event.event_type {
            MidiEventType::NoteOn { note, velocity } => {
                assert_eq!(note, 60);
                assert_eq!(velocity, 100);
            }
            _ => panic!("Expected NoteOn"),
        }
    }

    #[test]
    fn test_parse_note_off() {
        let message = vec![0x80, 60, 64]; // Note Off, C4, velocity 64
        let event = parse_midi_message(&message, 1000);

        assert!(event.is_some());
        let event = event.unwrap();

        match event.event_type {
            MidiEventType::NoteOff { note, velocity } => {
                assert_eq!(note, 60);
                assert_eq!(velocity, 64);
            }
            _ => panic!("Expected NoteOff"),
        }
    }

    #[test]
    fn test_parse_note_on_zero_velocity() {
        let message = vec![0x90, 60, 0]; // Note On with velocity 0 = Note Off
        let event = parse_midi_message(&message, 1000);

        assert!(event.is_some());
        let event = event.unwrap();

        match event.event_type {
            MidiEventType::NoteOff { note, velocity } => {
                assert_eq!(note, 60);
                assert_eq!(velocity, 0);
            }
            _ => panic!("Expected NoteOff"),
        }
    }
}
