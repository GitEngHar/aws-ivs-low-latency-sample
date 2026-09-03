# Implementation Plan

- [x] 1. Enable cross-origin access and persistence foundation
- [x] 1.1 Enable and configure CORS for the frontend origin
  - Activate the CORS middleware for the API
  - Restrict allowed origins to an explicit, environment-driven allowlist (not a wildcard)
  - Permit the HTTP methods and headers the frontend needs (GET, POST, the mock user id header)
  - Verify a preflight request from the frontend origin succeeds and a request from an unlisted origin does not receive permissive headers
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 1.2 Create the channel persistence model
  - Add a data store for a channel record capturing: owning mock user id, name, IVS channel identifier (ARN), ingest endpoint, playback URL, stream key value/identifier, channel type, and public/private state
  - Enforce required fields and a unique constraint on the IVS channel identifier
  - Choose field names that avoid collisions with reserved framework/language keywords
  - _Requirements: 3.2, 3.5_

- [x] 2. Build the IVS integration and mock-identity layers
- [x] 2.1 Extract IVS channel creation/update calls into a dedicated service
  - Wrap the external channel-creation call and the visibility-change call behind a small service used by the controller
  - Let failures from the external call propagate distinctly so callers can respond with an appropriate error rather than a generic failure
  - _Requirements: 3.1, 3.4, 5.3_

- [x] 2.2 Enforce the mock user identity on user-scoped requests
  - Extract the caller-supplied mock user id from incoming requests
  - Reject user-scoped requests that omit the id with a clear error response, before any external call or database work happens
  - Treat the id as an opaque owner value with no validation against a real identity system
  - _Requirements: 2.2, 2.3, 2.4_

- [x] 3. Implement the channel lifecycle API
- [x] 3.1 Persist a channel record on creation
  - On a create request, call the external channel-creation flow, then persist the returned channel data (including the stream key) tied to the requesting mock user, only after the external call succeeds
  - Respond with the persisted channel's identifying fields, keeping the stream key out of this response
  - Ensure a failed external call leaves no partial record behind
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3.2 Scope channel listing to the requesting owner
  - Replace the existing broad channel listing with a query against persisted records owned by the requesting mock user id
  - Return an empty list rather than an error when the owner has no channels
  - _Requirements: 4.1, 4.2, 4.5_

- [x] 3.3 Add single-channel detail retrieval for broadcasting
  - Add a way to fetch one persisted channel by id, scoped to the requesting owner, that includes the stream key needed to start a broadcast
  - Respond with a not-found error when the channel does not exist or is not owned by the requester
  - _Requirements: 4.4_

- [x] 3.4 Wire visibility-change actions to persisted channels
  - Update the existing public/private change actions to operate on a persisted channel identified by the request (instead of a hardcoded channel) and to require ownership by the requesting mock user
  - After a successful external visibility change, update the persisted channel's public/private state and respond with the updated state
  - Leave the persisted state unchanged when the external call fails, and respond with an error
  - Add routing for channel creation and single-channel retrieval alongside the existing action routes
  - _Requirements: 5.2, 5.3, 5.5_

- [x] 4. Add automated backend test coverage
- [x] 4.1 Cover the persistence model, IVS service wrapper, and identity enforcement with unit tests
  - Test required-field and uniqueness enforcement on the channel record
  - Test that the IVS service wrapper invokes the external call with the expected inputs for both creation and visibility change, using a stubbed external client
  - Test that a missing mock user id is rejected before any external/database work
  - _Requirements: 2.3, 3.2, 3.5, 5.3_

- [x] 4.2 Cover the channel lifecycle endpoints with request-level tests
  - Test that creating a channel persists a record and omits the stream key from the response
  - Test that listing only returns channels owned by the requesting user (seed more than one owner's channels)
  - Test that fetching single-channel detail includes the stream key and enforces ownership with a not-found response otherwise
  - Test that a visibility-change request updates the persisted state and rejects requests for channels not owned by the requester
  - _Requirements: 3.3, 4.1, 4.4, 5.2, 5.3_

- [x] 5. Wire the frontend to the backend API
- [x] 5.1 Add backend connectivity and mock identity configuration to the frontend
  - Add the backend base URL to the frontend's environment configuration flow
  - Add a fixed mock user id held by the frontend, available wherever API calls are made
  - _Requirements: 2.1, 6.3_

- [x] 5.2 Build a shared frontend API client for channel operations
  - Implement request functions for creating a channel, listing channels, fetching one channel's detail, and changing a channel's visibility
  - Include the mock user id on every user-scoped request
  - Surface network and non-success responses as errors that calling code can catch and display, rather than failing silently
  - _Requirements: 2.2, 6.1, 6.2_

- [x] 6. Build channel creation, listing, and selection in the broadcast UI
- [x] 6.1 Fetch and render the owner's channel list with a creation control
  - On load, fetch the current channel list and render it as a selectable list in the broadcast UI
  - Add a control to create a new channel, refreshing the list and reflecting the newly created channel afterward
  - _Requirements: 4.2, 4.3_

- [x] 6.2 Drive the broadcast client from the selected channel
  - When a channel is selected, fetch its detail (including stream key) and use it as the source of the ingest endpoint and stream key for starting a broadcast, replacing the static configuration previously used for these values
  - _Requirements: 4.4_

- [x] 7. Add the public/private toggle with a safe stop/restart sequence
- [x] 7.1 Stop the active broadcast and request the visibility change
  - Add a public/private toggle control reflecting the selected channel's current state
  - On activation, stop any active broadcast first, then request the visibility change for the selected channel from the backend
  - Prevent further toggle activation or manual broadcast start while a switch is in flight
  - _Requirements: 5.1, 5.2, 5.6_

- [x] 7.2 Restart broadcasting after a confirmed switch and handle failures
  - On a successful visibility change, restart the broadcast using the same channel credentials and update the displayed state
  - On a failed visibility-change request, surface the error to the broadcaster and leave the broadcast stopped rather than restarting automatically
  - _Requirements: 5.4, 5.5_

- [x] 8. Verify the end-to-end flow
- [x] 8.1 Exercise the full create-select-broadcast-toggle sequence manually
  - Create a channel from a fresh session and confirm it becomes selected and ready to broadcast
  - Select a previously created channel and start a broadcast using its credentials
  - Toggle visibility while broadcasting and confirm the stop/switch/restart sequence behaves as designed, including the failure path
  - _Requirements: All requirements_
