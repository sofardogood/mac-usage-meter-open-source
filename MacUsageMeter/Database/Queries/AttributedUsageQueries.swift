import Foundation

enum AttributedUsageQueries {
    static let insert = """
    INSERT INTO attributed_usage (
        captured_at_ms, application_name, bundle_identifier, destination_host,
        sent_bytes, received_bytes, estimated_watts
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    static let summaryByDestination = """
    SELECT application_name, bundle_identifier, destination_host,
           SUM(sent_bytes + received_bytes) AS total_bytes,
           CASE WHEN SUM(sent_bytes + received_bytes) > 0
                THEN SUM(estimated_watts * (sent_bytes + received_bytes)) / SUM(sent_bytes + received_bytes)
                ELSE NULL END AS estimated_watts
    FROM attributed_usage
    WHERE captured_at_ms >= ? AND captured_at_ms <= ?
    GROUP BY application_name, bundle_identifier, destination_host
    ORDER BY total_bytes DESC, application_name ASC
    """

    static let purge = "DELETE FROM attributed_usage WHERE captured_at_ms < ?"
}
