# Requirements Document

## Project Description (Input)
Connect the frontend (frontend/) to the Rails backend (live-control-plane/) for IVS channel management.

Requirements from the user:
- Wire up FE <-> Backend integration (backend already has a live/streams_controller with IVS list/create/change_to_private/change_to_public/playback_token/user_kick actions using aws-sdk-ivs, but create/list are not yet persisted to a DB, CORS is not enabled, and none of this is called from the frontend).
- A fixed mock user_id, held on the frontend, is sent to identify the "current user" (no real auth).
- Channel creation flow: FE calls backend to create an IVS channel; backend must persist the channel (including its stream key, ingest endpoint, playback URL, ARN, owner mock user_id, and public/private type) to the DB, not just return it transiently as today.
- FE should fetch the list of channels (scoped to the mock user) from the backend, let the user pick one, and use the selected channel's ingest endpoint/stream key to drive the existing broadcast.js flow (see frontend/broadcast.js which currently reads these from a local .env-derived config.js).
- Add a public/private toggle control in the broadcast UI: switching it should stop the current broadcast, call the backend to flip the channel's authorized/private setting (see streams#change_to_private / change_to_public), and immediately restart broadcasting once the switch completes.

Existing relevant code to account for:
- live-control-plane/app/controllers/live/streams_controller.rb (list, create, change_to_private, change_to_public, playback_token, user_kick — uses Aws::IVS::Client, has some hardcoded ARNs/user ids that need to become real params/DB lookups)
- live-control-plane/app/services/ivs_playback_token_service.rb
- live-control-plane/config/routes.rb (namespace :live; note `create` action exists on the controller but has no route yet)
- live-control-plane/config/initializers/cors.rb (rack-cors gem present but commented out — CORS is not currently enabled, needed for FE at localhost to call this API)
- No DB migrations/models exist yet (fresh Rails 8 app, sqlite3, solid_queue/solid_cache installed)
- frontend/broadcast.js, frontend/player.js, frontend/index.html, frontend/config.js (generated from frontend/.env) — currently frontend has no API client code, just direct IVS SDK usage with static/env-configured ingest endpoint, stream key, and playback URL

## Introduction

This feature connects the static frontend broadcast demo to the Rails `live-control-plane` API so that IVS channels are created and managed through the backend instead of being hardcoded in `frontend/.env`. The backend gains a `Channel` persistence layer (owner, IVS identifiers, stream key, playback URL, public/private state) behind a mock-user identity, and the frontend gains an API client, a channel creation/selection UI, and a public/private toggle that safely restarts the live broadcast when the channel's visibility changes.

## Requirements

### Requirement 1: Cross-origin API access
**Objective:** As a frontend developer, I want the Rails API to accept requests from the frontend's origin, so that browser JavaScript can call the backend without being blocked by CORS.

#### Acceptance Criteria
1. WHEN the frontend origin sends a cross-origin request with an allowed method (GET, POST) to any `/live/*` endpoint THEN the Channel Service SHALL respond with CORS headers that permit the request.
2. WHEN a browser sends a CORS preflight (`OPTIONS`) request to a `/live/*` endpoint THEN the Channel Service SHALL respond with a successful preflight response granting the required method and headers.
3. IF a request originates from a host not in the configured allowlist THEN the Channel Service SHALL NOT include permissive CORS headers in the response.

### Requirement 2: Mock user identity
**Objective:** As a demo user, I want a fixed mock user id to represent "me" without a real login system, so that channels can be scoped to an owner.

#### Acceptance Criteria
1. WHEN the frontend application loads THEN the Frontend SHALL hold a fixed mock user id value available to all API calls.
2. WHEN the Frontend calls any `/live/*` endpoint that is scoped to a user THEN the Frontend SHALL include the mock user id in the request (as a header or parameter).
3. WHEN the Channel Service receives a request that requires a user id AND the request does not include one THEN the Channel Service SHALL reject the request with an error response.
4. WHERE the Channel Service processes a user-scoped request THE Channel Service SHALL treat the supplied user id as an opaque owner identifier without validating it against a real authentication system.

### Requirement 3: Channel creation and persistence
**Objective:** As a broadcaster, I want to create a new IVS channel from the frontend, so that I get a channel backed by a persisted record I can reuse later.

#### Acceptance Criteria
1. WHEN the Frontend submits a create-channel request with the mock user id THEN the Channel Service SHALL call the AWS IVS API to create a new channel.
2. WHEN the AWS IVS API successfully creates a channel THEN the Channel Service SHALL persist a Channel record containing the channel ARN, ingest endpoint, stream key, playback URL, owner user id, and public/private type before responding to the request.
3. WHEN a Channel record has been persisted THEN the Channel Service SHALL respond to the Frontend with the persisted channel's identifying fields (id, ARN, ingest endpoint, playback URL, public/private type) excluding or explicitly marking the stream key as sensitive.
4. IF the AWS IVS API call fails during channel creation THEN the Channel Service SHALL respond with an error and SHALL NOT persist a partial Channel record.
5. WHEN a Channel record is persisted THEN the Channel Service SHALL store the stream_key value such that it is retrievable by the owning user for broadcasting.

### Requirement 4: Channel listing and selection
**Objective:** As a broadcaster, I want to see my previously created channels and pick one, so that I can start broadcasting to it without recreating a channel each time.

#### Acceptance Criteria
1. WHEN the Frontend requests the channel list with the mock user id THEN the Channel Service SHALL return only Channel records owned by that user id.
2. WHEN the Channel Service returns the channel list THEN the Channel Service SHALL include, for each channel, at minimum its id, ARN, ingest endpoint, playback URL, and public/private type.
3. WHEN the Frontend receives the channel list THEN the Frontend SHALL render the channels as a selectable list.
4. WHEN the broadcaster selects a channel from the list THEN the Frontend SHALL retrieve that channel's ingest endpoint and stream key from the Channel Service and use them to configure the broadcast client.
5. IF the mock user has no channels THEN the Channel Service SHALL return an empty list rather than an error.

### Requirement 5: Public/private visibility toggle with safe restart
**Objective:** As a broadcaster, I want to switch a channel between public and private while live, so that I can change who can view my stream without leaving the channel in an inconsistent state.

#### Acceptance Criteria
1. WHEN the broadcaster activates the public/private toggle for the currently selected channel THEN the Frontend SHALL stop the active broadcast before requesting the visibility change.
2. WHEN the Frontend has stopped the active broadcast THEN the Frontend SHALL call the Channel Service to change the selected channel's visibility to the requested mode (public or private).
3. WHEN the Channel Service successfully changes a channel's visibility via the AWS IVS API THEN the Channel Service SHALL update the persisted Channel record's public/private type and respond with the updated state.
4. WHEN the Frontend receives confirmation that the visibility change succeeded THEN the Frontend SHALL restart broadcasting to the same channel using its current ingest endpoint and stream key.
5. IF the visibility-change request to the Channel Service fails THEN the Frontend SHALL surface an error to the broadcaster and SHALL NOT restart the broadcast automatically.
6. WHILE the broadcast is stopped for a visibility switch THE Frontend SHALL prevent the broadcaster from triggering another toggle or manual start until the in-flight switch completes.

### Requirement 6: Frontend API client for the Channel Service
**Objective:** As a frontend developer, I want a single place that talks to the backend API, so that channel creation, listing, and visibility changes are consistent and reusable across the UI.

#### Acceptance Criteria
1. WHERE the Frontend needs to call the Channel Service THE Frontend SHALL use a shared API client module rather than duplicating fetch logic per feature.
2. WHEN an API call made by the Frontend's API client fails (network error or non-success HTTP status) THEN the API client SHALL surface an error that calling code can handle and display to the broadcaster.
3. WHEN the Frontend's API client makes a request to the Channel Service THEN the API client SHALL read the backend base URL from the frontend's existing environment configuration (`config.js`/`.env`) rather than hardcoding it.
