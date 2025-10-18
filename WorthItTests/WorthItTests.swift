//
//  WorthItTests.swift
//  WorthItTests
//
//  Created by Juan Manuel Fontes on 24.05.2025.
//

import Testing
import XCTest
@testable import WorthIt

struct WorthItTests {

    // MARK: - URL Parser Tests
    
    @Test func testURLParserValidYouTubeURLs() async throws {
        let testCases = [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/v/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ")
        ]
        
        for (urlString, expectedID) in testCases {
            guard let url = URL(string: urlString) else {
                #expect(false, "Invalid URL: \(urlString)")
                continue
            }
            
            do {
                let videoID = try URLParser.extractVideoID(from: url)
                #expect(videoID == expectedID, "Expected \(expectedID), got \(videoID) for URL: \(urlString)")
            } catch {
                #expect(false, "Failed to extract video ID from \(urlString): \(error)")
            }
        }
    }
    
    @Test func testURLParserInvalidURLs() async throws {
        let invalidURLs = [
            "https://www.youtube.com/watch",
            "https://www.youtube.com/watch?v=",
            "https://www.youtube.com/watch?v=invalid",
            "https://vimeo.com/123456789",
            "https://www.google.com",
            "not-a-url"
        ]
        
        for urlString in invalidURLs {
            guard let url = URL(string: urlString) else {
                #expect(false, "Invalid URL: \(urlString)")
                continue
            }
            
            do {
                _ = try URLParser.extractVideoID(from: url)
                #expect(false, "Should have failed for invalid URL: \(urlString)")
            } catch {
                // Expected to fail
                #expect(true, "Correctly failed for invalid URL: \(urlString)")
            }
        }
    }
    
    @Test func testURLParserFirstSupportedVideoURL() async throws {
        let testText = "Check out this video: https://www.youtube.com/watch?v=dQw4w9WgXcQ and also this one: https://youtu.be/anotherID"
        let url = URLParser.firstSupportedVideoURL(in: testText)
        
        #expect(url != nil, "Should find a supported video URL")
        #expect(url?.absoluteString.contains("dQw4w9WgXcQ") == true, "Should find the first video URL")
    }
    
    // MARK: - Models Tests
    
    @Test func testContentAnalysisDecoding() async throws {
        let jsonString = """
        {
            "summary": "Test summary",
            "longSummary": "Test long summary",
            "takeaways": ["Takeaway 1", "Takeaway 2"],
            "gemsOfWisdom": ["Gem 1"],
            "videoId": "test123",
            "videoTitle": "Test Video",
            "videoDurationSeconds": 120,
            "videoThumbnailUrl": "https://example.com/thumb.jpg",
            "viewerTips": ["Tip 1"],
            "sentimentSummary": "Positive sentiment",
            "controversyDetection": ["Controversy 1"],
            "topThemes": [
                {
                    "theme": "Test Theme",
                    "sentiment": "Positive",
                    "sentimentScore": 0.8,
                    "exampleComment": "Great video!"
                }
            ],
            "keyQuestions": [
                {
                    "question_text": "What is this about?",
                    "example_comment": "I wonder about this"
                }
            ],
            "categorizedComments": [
                {"index": 0, "category": "humor"},
                {"index": 1, "category": "insightful"}
            ],
            "spotlightComments": [
                {
                    "type": "most_insightful",
                    "comment_text": "Very insightful comment",
                    "author": "User1",
                    "reason": "Great analysis"
                }
            ],
            "suggestedQuestions": ["Question 1", "Question 2"]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let analysis = try decoder.decode(ContentAnalysis.self, from: data)
            #expect(analysis.summary == "Test summary")
            #expect(analysis.videoId == "test123")
            #expect(analysis.takeaways?.count == 2)
            #expect(analysis.topThemes?.count == 1)
            #expect(analysis.categorizedComments?.count == 2)
            #expect(analysis.suggestedQuestions?.count == 2)
        } catch {
            #expect(false, "Failed to decode ContentAnalysis: \(error)")
        }
    }
    
    @Test func testCommentInsightsDecoding() async throws {
        let jsonString = """
        {
            "videoId": "test123",
            "viewerTips": ["Tip 1", "Tip 2"],
            "overallCommentSentimentScore": 0.75,
            "contentDepthScore": 0.85,
            "suggestedQuestions": ["What is this about?", "How does it work?"]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let insights = try decoder.decode(CommentInsights.self, from: data)
            #expect(insights.videoId == "test123")
            #expect(insights.overallCommentSentimentScore == 0.75)
            #expect(insights.contentDepthScore == 0.85)
            #expect(insights.suggestedQuestions.count == 2)
        } catch {
            #expect(false, "Failed to decode CommentInsights: \(error)")
        }
    }
    
    @Test func testChatMessageCreation() async throws {
        let message = ChatMessage(content: "Test message", isUser: true)
        
        #expect(message.content == "Test message")
        #expect(message.isUser == true)
        #expect(message.id != UUID())
    }
    
    @Test func testScoreBreakdownCreation() async throws {
        let breakdown = ScoreBreakdown(
            contentDepthScore: 0.8,
            commentSentimentScore: 0.7,
            hasComments: true,
            contentDepthRaw: 0.8,
            commentSentimentRaw: 0.7,
            finalScore: 75,
            videoTitle: "Test Video",
            positiveCommentThemes: ["Great content"],
            negativeCommentThemes: ["Could be better"]
        )
        
        #expect(breakdown.contentDepthScore == 0.8)
        #expect(breakdown.commentSentimentScore == 0.7)
        #expect(breakdown.hasComments == true)
        #expect(breakdown.finalScore == 75)
        #expect(breakdown.videoTitle == "Test Video")
        #expect(breakdown.positiveCommentThemes.count == 1)
        #expect(breakdown.negativeCommentThemes.count == 1)
    }
    
    // MARK: - String Extensions Tests
    
    @Test func testStringTruncate() async throws {
        let longString = "This is a very long string that needs to be truncated"
        let truncated = longString.truncate(to: 10)
        
        #expect(truncated.count <= 13) // 10 + "..."
        #expect(truncated.hasSuffix("..."))
        
        let shortString = "Short"
        let notTruncated = shortString.truncate(to: 10)
        #expect(notTruncated == shortString)
    }
    
    @Test func testStringStripTimestamps() async throws {
        let textWithTimestamps = "[00:00:15] Hello world [00:00:30] How are you? (01:30) Good morning"
        let stripped = textWithTimestamps.stripTimestamps()
        
        #expect(!stripped.contains("[00:00:15]"))
        #expect(!stripped.contains("(01:30)"))
        #expect(stripped.contains("Hello world"))
        #expect(stripped.contains("How are you?"))
    }
    
    // MARK: - Network Error Tests
    
    @Test func testNetworkErrorLocalizedDescription() async throws {
        let serverError = NetworkError.serverUnavailable
        let rateLimitError = NetworkError.rateLimited
        let decodingError = NetworkError.decodingFailed
        
        #expect(!serverError.localizedDescription.isEmpty)
        #expect(!rateLimitError.localizedDescription.isEmpty)
        #expect(!decodingError.localizedDescription.isEmpty)
        
        #expect(serverError.localizedDescription.contains("unavailable"))
        #expect(rateLimitError.localizedDescription.contains("Too many requests"))
        #expect(decodingError.localizedDescription.contains("couldn't read"))
    }
    
    // MARK: - View State Tests
    
    @Test func testViewStateEquality() async throws {
        let idle = ViewState.idle
        let processing = ViewState.processing
        let showingOptions = ViewState.showingInitialOptions
        
        #expect(idle == ViewState.idle)
        #expect(processing == ViewState.processing)
        #expect(showingOptions == ViewState.showingInitialOptions)
        #expect(idle != processing)
        
        #expect(processing.isProcessing == true)
        #expect(idle.isProcessing == false)
    }
    
    // MARK: - User Friendly Error Tests
    
    @Test func testUserFriendlyErrorCreation() async throws {
        let error = UserFriendlyError(
            message: "Test error message",
            canRetry: true,
            videoIdForRetry: "test123"
        )
        
        #expect(error.message == "Test error message")
        #expect(error.canRetry == true)
        #expect(error.videoIdForRetry == "test123")
    }
    
    // MARK: - App Constants Tests
    
    @Test func testAppConstants() async throws {
        #expect(!AppConstants.appGroupID.isEmpty)
        #expect(!AppConstants.bundleID.isEmpty)
        #expect(!AppConstants.urlScheme.isEmpty)
        #expect(!AppConstants.apiBaseURLKey.isEmpty)
        
        #expect(AppConstants.urlScheme == "worthitai")
        #expect(AppConstants.apiBaseURLKey == "API_PROXY_BASE_URL")
    }
    
    // MARK: - Content Analysis Placeholder Tests
    
    @Test func testContentAnalysisPlaceholder() async throws {
        let placeholder = ContentAnalysis.placeholder()
        
        #expect(placeholder.summary == "")
        #expect(placeholder.longSummary == "")
        #expect(placeholder.videoId == "")
        #expect(placeholder.videoTitle == "")
        #expect(placeholder.takeaways?.isEmpty == true)
        #expect(placeholder.gemsOfWisdom?.isEmpty == true)
    }
    
    // MARK: - JSON Sanitization Tests
    
    @Test func testSanitizedJSONData() async throws {
        let jsonWithMarkdown = "```json\n{\"test\": \"value\"}\n```"
        let sanitized = sanitizedJSONData(from: jsonWithMarkdown)
        
        #expect(sanitized != nil)
        
        if let data = sanitized {
            let decoder = JSONDecoder()
            do {
                let dict = try decoder.decode([String: String].self, from: data)
                #expect(dict["test"] == "value")
            } catch {
                #expect(false, "Failed to decode sanitized JSON: \(error)")
            }
        }
    }
    
    @Test func testSanitizedJSONDataInvalidInput() async throws {
        let invalidJSON = "This is not JSON"
        let sanitized = sanitizedJSONData(from: invalidJSON)
        
        #expect(sanitized == nil)
    }
}
