#!/usr/bin/env python3
"""Read-only HTTP contracts for the authorized FL-Tiya development project.

Only creates temporary development login sessions; no likes, comments, profiles,
friendships, blocks, media or wallet rows are changed. Tokens stay in memory.
"""
import json
from import_development_clips import Client

PROJECT = {'project_ref': 'gpstwmffctwqlcakmvgw'}


def rpc(client, name, params):
    status, payload = client.call('/rest/v1/rpc/' + name, method='POST',
                                  data=json.dumps(params).encode())
    assert status == 200, name + ' HTTP contract failed: ' + str(status)
    return json.loads(payload)


def verify():
    client = Client(PROJECT, 'Development Beta')
    try:
        status, payload = client.call('/rest/v1/video_posts?select=id&status=eq.approved')
        assert status == 200, 'Approved clip read failed'
        clips = json.loads(payload)
        assert len(clips) == 10, 'Expected ten approved feed clips'
        for clip in clips:
            state = rpc(client, 'clip_social_state', {'target_clip_id': clip['id']})
            assert set(state) == {'uploader', 'like_count', 'comment_count', 'is_liked', 'is_following'}
            assert type(state['like_count']) is int and state['like_count'] >= 0
            assert type(state['comment_count']) is int and state['comment_count'] >= 0
            assert type(state['is_following']) is bool
            assert type(state['is_liked']) is bool
            uploader = state['uploader']
            assert uploader is None or all(k in uploader for k in ('id', 'handle', 'display_name', 'bio', 'avatar_path'))
            if uploader is not None:
                follow = rpc(client, 'player_follow_state', {'target_user_id': uploader['id']})
                assert set(follow) == {'is_following', 'follower_count'}
                assert type(follow['is_following']) is bool and type(follow['follower_count']) is int
            comments = rpc(client, 'clip_comments', {'target_clip_id': clip['id']})
            assert isinstance(comments, list)
            for comment in comments:
                assert all(k in comment for k in ('id', 'clip_id', 'author', 'body', 'status', 'created_at'))
                assert comment['status'] in ('approved', 'pending')
        for game in (None, 'zenless-zone-zero'):
            players = rpc(client, 'discover_community_players', {'target_game_id': game, 'search_query': ''})
            assert isinstance(players, list)
            for player in players:
                assert player['id'] != client.user_id
                assert player['relationship'] in ('none', 'friends', 'incoming', 'outgoing')
                assert all(k in player for k in ('id', 'handle', 'display_name', 'bio', 'avatar_path', 'request_id'))
        blocks = rpc(client, 'list_blocked_players', {'before_blocked_at': None, 'before_user_id': None})
        assert isinstance(blocks, list) and len(blocks) <= 50
        assert rpc(client, 'list_blocked_players', {}) == blocks, 'Default cursor differs'
        for name, params in (
            ('clip_social_state', {'target_clip_id': clips[0]['id']}),
            ('clip_comments', {'target_clip_id': clips[0]['id']}),
            ('discover_community_players', {}),
            ('list_blocked_players', {}),
            ('player_follow_state', {'target_user_id': client.user_id}),
            ('set_player_followed', {'target_user_id': client.user_id, 'followed': True}),
            ('open_direct_conversation', {'target_user_id': client.user_id}),
            ('conversation_messaging_state', {'target_conversation_id': client.user_id}),
        ):
            status, _ = client.call('/rest/v1/rpc/' + name, method='POST',
                                    data=json.dumps(params).encode(), anonymous=True)
            assert status in (400, 401, 403), 'Unauthenticated RPC unexpectedly available'
        print(json.dumps({'status': 'passed', 'approved_clips': len(clips),
                          'clip_state_and_comment_contracts': len(clips),
                          'community_queries': 2, 'blocklist_default_and_explicit_cursor': True,
                          'unauthenticated_rpc_denials': 8,
                          'business_data_mutated': False}))
    finally:
        client.close()


if __name__ == '__main__':
    verify()
