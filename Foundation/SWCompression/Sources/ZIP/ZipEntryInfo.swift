// Copyright (c) 2021 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import BitByteData
import Foundation

/// Provides access to information about an entry from the ZIP container.
public struct ZipEntryInfo: ContainerEntryInfo {
    // MARK: ContainerEntryInfo

    public let name: String

    public let size: Int?

    public let type: ContainerEntryType

    /**
      Entry's last access time (`nil`, if not available).

      Set from different sources in the following preference order:
      1. Extended timestamp extra field (most common on UNIX-like systems).
      2. NTFS extra field.
     */
    public let accessTime: Date?

    /**
     Entry's creation time (`nil`, if not available).

     Set from different sources in the following preference order:
     1. Extended timestamp extra field (most common on UNIX-like systems).
     2. NTFS extra field.
     */
    public let creationTime: Date?

    /**
     Entry's last modification time.

     Set from different sources in the following preference order:
     1. Extended timestamp extra field (most common on UNIX-like systems).
     2. NTFS extra field.
     3. ZIP container's own storage (in Central Directory entry).
     */
    public let modificationTime: Date?

    /**
     Entry's permissions in POSIX format.
     May have meaningless value if origin file system's attributes weren't POSIX compatible.
     */
    public let permissions: Permissions?

    // MARK: ZIP specific

    /// Entry's comment.
    public let comment: String

    /**
     Entry's external file attributes. ZIP internal property.
     May be useful when origin file system's attributes weren't POSIX compatible.
     */
    public let externalFileAttributes: UInt32

    /// Entry's attributes in DOS format.
    public let dosAttributes: DosAttributes?

    /// True, if entry is likely to be text or ASCII file.
    public let isTextFile: Bool

    /// File system type of container's origin.
    public let fileSystemType: FileSystemType

    /// Entry's compression method.
    public let compressionMethod: CompressionMethod

    /**
     ID of entry's owner.

     Set from different sources in the following preference order, if possible:
     1. Info-ZIP New Unix extra field.
     2. Info-ZIP Unix extra field.
     */
    public let ownerID: Int?

    /**
     ID of the group of entry's owner.

     Set from different sources in the following preference order, if possible:
     1. Info-ZIP New Unix extra field.
     2. Info-ZIP Unix extra field.
     */
    public let groupID: Int?

    /**
     Entry's custom extra fields from both Central Directory and Local Header.

     - Note: No particular order of extra fields is guaranteed.
     */
    public let customExtraFields: [ZipExtraField]

    /// CRC32 of entry's data.
    public let crc: UInt32

    init(_: LittleEndianByteReader, _ cdEntry: ZipCentralDirectoryEntry, _ localHeader: ZipLocalHeader,
         _ hasDataDescriptor: Bool)
    {
        name = cdEntry.fileName

        // Set Modification Time.
        if let mtime = cdEntry.extendedTimestampExtraField?.mtime {
            // Extended Timestamp extra field.
            modificationTime = Date(timeIntervalSince1970: TimeInterval(mtime))
        } else if let mtime = cdEntry.ntfsExtraField?.mtime {
            // NTFS extra field.
            modificationTime = Date(mtime)
        } else {
            // Native ZIP modification time.
            let dosDate = cdEntry.lastModFileDate.toInt()

            let day = dosDate & 0x1F
            let month = (dosDate & 0x1E0) >> 5
            let year = 1980 + ((dosDate & 0xFE00) >> 9)

            let dosTime = cdEntry.lastModFileTime.toInt()

            let seconds = 2 * (dosTime & 0x1F)
            let minutes = (dosTime & 0x7E0) >> 5
            let hours = (dosTime & 0xF800) >> 11

            modificationTime = DateComponents(calendar: Calendar.current, timeZone: TimeZone.current,
                                              year: year, month: month, day: day,
                                              hour: hours, minute: minutes, second: seconds).date
        }

        // Set Creation Time.
        if let ctime = localHeader.extendedTimestampExtraField?.ctime {
            // Extended Timestamp extra field.
            creationTime = Date(timeIntervalSince1970: TimeInterval(ctime))
        } else if let ctime = cdEntry.ntfsExtraField?.ctime {
            // NTFS extra field.
            creationTime = Date(ctime)
        } else {
            creationTime = nil
        }

        // Set Creation Time.
        if let atime = localHeader.extendedTimestampExtraField?.atime {
            // Extended Timestamp extra field.
            accessTime = Date(timeIntervalSince1970: TimeInterval(atime))
        } else if let atime = cdEntry.ntfsExtraField?.atime {
            // NTFS extra field.
            accessTime = Date(atime)
        } else {
            accessTime = nil
        }

        size = (hasDataDescriptor ? cdEntry.uncompSize : localHeader.uncompSize).toInt()

        externalFileAttributes = cdEntry.externalFileAttributes
        permissions = Permissions(rawValue: (0x0FFF_0000 & cdEntry.externalFileAttributes) >> 16)
        dosAttributes = DosAttributes(rawValue: 0xFF & cdEntry.externalFileAttributes)

        // Set entry type.
        if let unixType = ContainerEntryType((0xF000_0000 & cdEntry.externalFileAttributes) >> 16) {
            type = unixType
        } else if let dosAttributes = self.dosAttributes {
            if dosAttributes.contains(.directory) {
                type = .directory
            } else {
                type = .regular
            }
        } else if size == 0, cdEntry.fileName.last == "/" {
            type = .directory
        } else {
            type = .regular
        }

        comment = cdEntry.fileComment
        isTextFile = cdEntry.internalFileAttributes & 0x1 != 0
        fileSystemType = FileSystemType(cdEntry.versionMadeBy)
        compressionMethod = CompressionMethod(localHeader.compressionMethod)
        ownerID = localHeader.infoZipNewUnixExtraField?.uid ?? localHeader.infoZipUnixExtraField?.uid
        groupID = localHeader.infoZipNewUnixExtraField?.gid ?? localHeader.infoZipUnixExtraField?.gid
        crc = hasDataDescriptor ? cdEntry.crc32 : localHeader.crc32

        // Custom extra fields.
        var customExtraFields = cdEntry.customExtraFields
        customExtraFields.append(contentsOf: localHeader.customExtraFields)
        self.customExtraFields = customExtraFields
    }
}
