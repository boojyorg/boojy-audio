/// Decode a percent-encoded CSV field produced by the engine's
/// `encode_csv_field` (engine/src/api/helpers.rs) — see C34.
///
/// The engine escapes `%`, `,` and `;` in free-text fields (track names) so a
/// name like "Drums, Kit" can't shift CSV fields or split `;`-joined entries.
/// Keep the two implementations in sync.
String decodeCsvField(String field) {
  // `%25` last, so a literal "%2C" typed into a name ("%252C" on the wire)
  // decodes back exactly.
  return field
      .replaceAll('%3B', ';')
      .replaceAll('%2C', ',')
      .replaceAll('%25', '%');
}
