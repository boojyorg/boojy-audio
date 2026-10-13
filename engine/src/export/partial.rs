//! Export files are written beside their final names under temporary ones and
//! moved into place only when the whole export has finished. Cancel, or a
//! failure, then never leaves a half-written file, nor replaces a file that
//! was already there.

use super::ExportProgressState;
use std::path::{Path, PathBuf};

/// The temporary files of one export. Any not moved into place by
/// [`Self::commit`] are deleted when this is dropped (an early return).
#[derive(Default)]
pub struct PartialFiles {
    /// (temporary, final) paths.
    files: Vec<(PathBuf, PathBuf)>,
}

impl PartialFiles {
    /// Where to write the file that will end up at `path`:
    /// `.<name>.partial.<ext>` in the same folder (hidden, with the extension
    /// kept).
    pub fn path_for(&mut self, path: &Path) -> PathBuf {
        let name = path
            .file_stem()
            .map_or_else(Default::default, |n| n.to_string_lossy());
        let ext = path
            .extension()
            .map_or_else(Default::default, |e| e.to_string_lossy());
        let partial = path.with_file_name(format!(".{name}.partial.{ext}"));
        self.files.push((partial.clone(), path.to_path_buf()));
        partial
    }

    /// Move every file into place, unless the export was cancelled: then
    /// they're all deleted and this returns `Err("Export cancelled")`.
    pub fn commit(mut self, progress: &ExportProgressState) -> Result<(), String> {
        if progress.is_cancelled() {
            return Err("Export cancelled".to_string());
        }
        for (partial, path) in std::mem::take(&mut self.files) {
            std::fs::rename(&partial, &path).map_err(|e| {
                let _ = std::fs::remove_file(&partial);
                format!("Couldn't save {}: {e}", path.display())
            })?;
        }
        Ok(())
    }
}

impl Drop for PartialFiles {
    fn drop(&mut self) {
        for (partial, _) in &self.files {
            let _ = std::fs::remove_file(partial);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ExportProgressState, PartialFiles};

    fn dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("boojy_partial_{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_finished_export_moves_into_place() {
        let dir = dir("commit");
        let path = dir.join("Song.wav");
        let mut files = PartialFiles::default();
        let partial = files.path_for(&path);
        assert_eq!(partial, dir.join(".Song.partial.wav"));
        std::fs::write(&partial, b"new").unwrap();
        files.commit(&ExportProgressState::new()).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"new");
        assert!(!partial.exists());
    }

    #[test]
    fn a_cancelled_export_leaves_the_old_file_alone() {
        let dir = dir("cancel");
        let path = dir.join("Song.wav");
        std::fs::write(&path, b"old").unwrap();
        let progress = ExportProgressState::new();
        let mut files = PartialFiles::default();
        let partial = files.path_for(&path);
        std::fs::write(&partial, b"half").unwrap();
        progress.cancel();
        assert_eq!(files.commit(&progress), Err("Export cancelled".to_string()));
        assert_eq!(std::fs::read(&path).unwrap(), b"old");
        assert!(!partial.exists());
    }

    #[test]
    fn a_failed_export_cleans_up_on_the_way_out() {
        let dir = dir("drop");
        let path = dir.join("Song.mp3");
        let partial = {
            let mut files = PartialFiles::default();
            let partial = files.path_for(&path);
            std::fs::write(&partial, b"half").unwrap();
            partial
        };
        assert!(!partial.exists());
        assert!(!path.exists());
    }
}
