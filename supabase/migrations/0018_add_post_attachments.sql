-- Add attachment_urls column to posts table for storing file and image URLs
ALTER TABLE posts ADD COLUMN attachment_urls TEXT[] DEFAULT '{}';

-- Create index for faster queries on posts with attachments
CREATE INDEX idx_posts_with_attachments ON posts((attachment_urls IS NOT NULL))
WHERE array_length(attachment_urls, 1) > 0;
