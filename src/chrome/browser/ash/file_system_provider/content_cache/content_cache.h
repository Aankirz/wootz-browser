// Copyright 2024 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_ASH_FILE_SYSTEM_PROVIDER_CONTENT_CACHE_CONTENT_CACHE_H_
#define CHROME_BROWSER_ASH_FILE_SYSTEM_PROVIDER_CONTENT_CACHE_CONTENT_CACHE_H_

#include "base/files/file_error_or.h"
#include "base/files/file_path.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ash/file_system_provider/content_cache/content_lru_cache.h"
#include "chrome/browser/ash/file_system_provider/opened_cloud_file.h"
#include "chrome/browser/ash/file_system_provider/provided_file_system_interface.h"

namespace ash::file_system_provider {

using FileErrorCallback = base::OnceCallback<void(base::File::Error)>;
using OnItemEvictedCallback =
    base::RepeatingCallback<void(const base::FilePath&)>;

// Alias to explain the inner int indicates `bytes_read`.
using FileErrorOrBytesRead = base::FileErrorOr<int>;

// When the removal process finishes, this defines the total number of items
// removed along with the total bytes removed.
struct RemovedItemStats {
  int64_t num_items = 0;
  int64_t bytes_removed = 0;
};

using RemovedItemStatsCallback = base::OnceCallback<void(RemovedItemStats)>;

// The content cache for every mounted FSP. This will serve as the single point
// of orchestration between the LRU cache and the disk persistence layer.
class ContentCache {
 public:
  virtual ~ContentCache() = default;

  // Sets the maximum size of the cache. If the current number of items exceeds
  // the number set, excess items will be evicted. Call `RemoveItems` to remove
  // the evicted items from the cache.
  virtual void SetMaxCacheItems(size_t max_cache_items) = 0;

  // Start reading bytes defined by `file` from the content cache. Returns true
  // when the bytes exist in the content cache and can be read (the actual bytes
  // will be stored in the `buffer` and `callback` invoked on finish) and false
  // if the bytes don't exist.
  virtual void ReadBytes(
      const OpenedCloudFile& file,
      scoped_refptr<net::IOBuffer> buffer,
      int64_t offset,
      int length,
      ProvidedFileSystemInterface::ReadChunkReceivedCallback callback) = 0;

  // Start writing bytes into the cache. Returns true if the bytes are able to
  // be written, currently this means:
  //   - `file` must contain a non-empty version_tag field.
  //   - If the file is already in the cache, the `offset` must be the next
  //     contiguous chunk to be written.
  //   - No other writer must be writing to the file at the moment
  // If any conditions are not satisfied, return false.
  virtual void WriteBytes(const OpenedCloudFile& file,
                          scoped_refptr<net::IOBuffer> buffer,
                          int64_t offset,
                          int length,
                          FileErrorCallback callback) = 0;

  // Reads and writes are performed in "chunks". An attempt is made to re-use
  // open file descriptors to avoid opening/closing them on every chunk request.
  // This requires any N requests of `ReadBytes` or `WriteBytes` to be
  // followed by a `CloseFile` to ensure any open file descriptors are properly
  // cleaned up.
  virtual void CloseFile(const OpenedCloudFile& file) = 0;

  // Load files from the content cache directory and the SQLite database. In the
  // event files have been orphaned (i.e. they are on disk with no DB entry or
  // vice versa) then prune them appropriately.
  virtual void LoadFromDisk(base::OnceClosure callback) = 0;

  // Returns the file paths of the cached files on disk, in their most recently
  // used order.
  virtual std::vector<base::FilePath> GetCachedFilePaths() = 0;

  // Called with the changes in the file system. This potentially indicates
  // cached files are deleted or changes.
  virtual void Notify(ProvidedFileSystemObserver::Changes& changes) = 0;

  // Evict the item with path `file_path` from the cache, if it exists. The item
  // is inaccessible from this point onwards despite it remaining on disk and
  // the database. It will be removed when `RemoveItems()` is called.
  virtual void Evict(const base::FilePath& file_path) = 0;

  // Call this on_item_evicted_callback with the item's FSP path when it is
  // evicted.
  virtual void SetOnItemEvictedCallback(
      OnItemEvictedCallback on_item_evicted_callback) = 0;

  // Remove items which have their `evicted` bool set to true. If an
  // removal is already in progress, the callback will be queued to be called
  // with the current stats of the in progress removal.
  virtual void RemoveItems(RemovedItemStatsCallback callback) = 0;

  // A struct of size information pertaining to this cache instance.
  struct SizeInfo {
    int64_t max_bytes_on_disk = 0;
    int64_t total_bytes_on_disk = 0;
  };

  // Helper methods to get and set size information.
  virtual const SizeInfo GetSize() const = 0;
  virtual void SetMaxBytesOnDisk(int64_t max_bytes_on_disk) = 0;

  // Returns a `base::WeakPtr`.
  virtual base::WeakPtr<ContentCache> GetWeakPtr() = 0;
};

}  // namespace ash::file_system_provider

#endif  // CHROME_BROWSER_ASH_FILE_SYSTEM_PROVIDER_CONTENT_CACHE_CONTENT_CACHE_H_
