import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

import 'package:blackhole/Helpers/format.dart';

class SaavnAPI {
  List preferredLanguages = Hive.box('settings')
      .get('preferredLanguage', defaultValue: ['Hindi']) as List;
  Map<String, String> headers = {};
  String baseUrl = 'www.jiosaavn.com';
  String apiStr = '/api.php?_format=json&_marker=0&api_version=4&ctx=web6dot0';
  Box settingsBox = Hive.box('settings');
  Map<String, String> endpoints = {
    'homeData': '__call=webapi.getLaunchData',
    'topSearches': '__call=content.getTopSearches',
    'getResult': '__call=search.getResults',
  };

  Future<Response> getResponse(String params,
      {bool usev4 = true, bool useProxy = false}) async {
    Uri url;
    if (!usev4) {
      url = Uri.https(
          baseUrl, '$apiStr&$params'.replaceAll('&api_version=4', ''));
    } else {
      url = Uri.https(baseUrl, '$apiStr&$params');
    }
    preferredLanguages =
        preferredLanguages.map((lang) => lang.toLowerCase()).toList();
    final String languageHeader = 'L=${preferredLanguages.join('%2C')}';
    headers = {'cookie': languageHeader, 'Accept': '*/*'};

    if (useProxy && settingsBox.get('useProxy', defaultValue: false) as bool) {
      final proxyIP = settingsBox.get('proxyIp');
      final proxyPort = settingsBox.get('proxyPort');
      final HttpClient httpClient = HttpClient();
      httpClient.findProxy = (uri) {
        return 'PROXY $proxyIP:$proxyPort;';
      };
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => Platform.isAndroid;
      final IOClient myClient = IOClient(httpClient);
      return myClient.get(url, headers: headers);
    }

    return get(url, headers: headers);
  }

  Future<Map> fetchHomePageData() async {
    Map result = {};
    try {
      final res = await getResponse(endpoints['homeData']!);
      if (res.statusCode == 200) {
        final Map data = json.decode(res.body) as Map;
        result = await FormatResponse().formatHomePageData(data);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in fetchHomePageData: $e');
    }
    return result;
  }

  Future<List<String>> getTopSearches() async {
    List<String> result = [];
    try {
      final res = await getResponse(endpoints['topSearches']!, useProxy: true);
      if (res.statusCode == 200) {
        final List getMain = json.decode(res.body) as List;
        result = getMain.map((element) {
          return element['title'].toString();
        }).toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in getTopSearches: $e');
    }
    return result;
  }

  Future<List> fetchSongSearchResults(String searchQuery, String count) async {
    List searchedList = [];
    final String params =
        "p=1&q=$searchQuery&n=$count&${endpoints['getResult']}";

    try {
      final res = await getResponse(params, useProxy: true);
      if (res.statusCode == 200) {
        final Map getMain = json.decode(res.body) as Map;
        final List responseList = getMain['results'] as List;
        searchedList =
            await FormatResponse().formatSongsResponse(responseList, 'song');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in fetchSongSearchResults: $e');
    }
    return searchedList;
  }

  Future<List<Map>> fetchSearchResults(String searchQuery) async {
    final Map<String, List> result = {};
    final Map<int, String> position = {};
    List searchedAlbumList = [];
    List searchedPlaylistList = [];
    List searchedArtistList = [];
    List searchedTopQueryList = [];

    final String params =
        '__call=autocomplete.get&cc=in&includeMetaTags=1&query=$searchQuery';

    final res = await getResponse(params, usev4: false, useProxy: true);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List albumResponseList = getMain['albums']['data'] as List;
      position[getMain['albums']['position'] as int] = 'Albums';
      final List playlistResponseList = getMain['playlists']['data'] as List;
      position[getMain['playlists']['position'] as int] = 'Playlists';
      final List artistResponseList = getMain['artists']['data'] as List;
      position[getMain['artists']['position'] as int] = 'Artists';
      final List topQuery = getMain['topquery']['data'] as List;

      searchedAlbumList = await FormatResponse()
          .formatAlbumResponse(albumResponseList, 'album');
      if (searchedAlbumList.isNotEmpty) result['Albums'] = searchedAlbumList;

      searchedPlaylistList = await FormatResponse()
          .formatAlbumResponse(playlistResponseList, 'playlist');
      if (searchedPlaylistList.isNotEmpty) {
        result['Playlists'] = searchedPlaylistList;
      }

      searchedArtistList = await FormatResponse()
          .formatAlbumResponse(artistResponseList, 'artist');
      if (searchedArtistList.isNotEmpty) result['Artists'] = searchedArtistList;

      if (topQuery.isNotEmpty &&
          (topQuery[0]['type'] == 'playlist' ||
              topQuery[0]['type'] == 'artist' ||
              topQuery[0]['type'] == 'album')) {
        position[getMain['topquery']['position'] as int] = 'Top Result';
        position[getMain['songs']['position'] as int] = 'Songs';

        switch (topQuery[0]['type'] as String) {
          case 'artist':
            searchedTopQueryList =
                await FormatResponse().formatAlbumResponse(topQuery, 'artist');
            break;
          case 'album':
            searchedTopQueryList =
                await FormatResponse().formatAlbumResponse(topQuery, 'album');
            break;
          case 'playlist':
            searchedTopQueryList = await FormatResponse()
                .formatAlbumResponse(topQuery, 'playlist');
            break;
          default:
            break;
        }
        if (searchedTopQueryList.isNotEmpty) {
          result['Top Result'] = searchedTopQueryList;
        }
      } else {
        if (topQuery.isNotEmpty && topQuery[0]['type'] == 'song') {
          position[getMain['topquery']['position'] as int] = 'Songs';
        } else {
          position[getMain['songs']['position'] as int] = 'Songs';
        }
      }
    }
    return [result, position];
  }

  Future<List<Map>> fetchAlbums(String searchQuery, String type) async {
    List<Map> searchedList = [];
    String? params;
    if (type == 'playlist') {
      params = 'p=1&q=$searchQuery&n=20&__call=search.getPlaylistResults';
    }
    if (type == 'album') {
      params = 'p=1&q=$searchQuery&n=20&__call=search.getAlbumResults';
    }
    if (type == 'artist') {
      params = 'p=1&q=$searchQuery&n=20&__call=search.getArtistResults';
    }

    final res = await getResponse(params!);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List responseList = getMain['results'] as List;
      searchedList =
          await FormatResponse().formatAlbumResponse(responseList, type);
    }
    return searchedList;
  }

  Future<List> fetchAlbumSongs(String albumId) async {
    List searchedList = [];
    final String params =
        '__call=content.getAlbumDetails&cc=in&albumid=$albumId';
    final res = await getResponse(params);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List responseList = getMain['list'] as List;
      searchedList =
          await FormatResponse().formatSongsResponse(responseList, 'album');
    }
    return searchedList;
  }

  Future<Map<String, List>> fetchArtistSongs(String artistToken) async {
    final Map<String, List> data = {};
    final String params =
        '__call=webapi.get&type=artist&p=&n_song=50&n_album=50&sub_type=&category=&sort_order=&includeMetaTags=0&token=$artistToken';
    final res = await getResponse(params);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List topSongsResponseList = getMain['topSongs'] as List;
      final List topAlbumsResponseList = getMain['topAlbums'] as List;
      // List singlesResponseList = getMain["singles"];
      // List latestReleaseResponseList = getMain["latest_release"];
      // List dedicatedArtistPlaylistResponseList = [];
      // if (getMain["dedicated_artist_playlist"] is List) {
      //   dedicatedArtistPlaylistResponseList =
      //       getMain["dedicated_artist_playlist"];
      // }
      // List featuredArtistPlaylistResponseList = [];
      // if (getMain["featured_artist_playlist"] is List) {
      //   featuredArtistPlaylistResponseList =
      //       getMain["featured_artist_playlist"];
      // }

      final List topSongsSearchedList = await FormatResponse()
          .formatSongsResponse(topSongsResponseList, 'song');
      if (topSongsSearchedList.isNotEmpty) {
        data['Top Songs'] = topSongsSearchedList;
      }

      final List topAlbumsSearchedList = await FormatResponse()
          .formatArtistTopAlbumsResponse(topAlbumsResponseList);
      if (topAlbumsSearchedList.isNotEmpty) {
        data['Top Albums'] = topAlbumsSearchedList;
      }

      // List latestReleaseSearchedList = await FormatResponse()
      // .formatSongsResponse(latestReleaseResponseList, 'songs');
      // if (latestReleaseSearchedList.isNotEmpty)
      // data['Latest Release'] = latestReleaseSearchedList;

      // List singlesSearchedList = await FormatResponse()
      // .formatSongsResponse(singlesResponseList, 'songs');
      // if (singlesSearchedList.isNotEmpty) data['Singles'] = singlesSearchedList;

      // List dedicatedArtistPlaylistSearchedList = await FormatResponse()
      //     .formatArtistDedicatedArtistPlaylistResponse(
      //         dedicatedArtistPlaylistResponseList);
      // if (dedicatedArtistPlaylistSearchedList.isNotEmpty)
      //   data['Dedicated Artist Playlist'] = dedicatedArtistPlaylistSearchedList;

      // List featuredArtistPlaylistSearchedList = await FormatResponse()
      //     .formatArtistFeaturedArtistPlaylistResponse(
      //         featuredArtistPlaylistResponseList);
      // if (featuredArtistPlaylistSearchedList.isNotEmpty)
      //   data['Featured Artist Playlist'] = featuredArtistPlaylistSearchedList;
    }
    return data;
  }

  Future<List> fetchPlaylistSongs(String playlistId) async {
    List searchedList = [];
    final String params = '__call=playlist.getDetails&cc=in&listid=$playlistId';
    final res = await getResponse(params);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List responseList = getMain['list'] as List;
      searchedList =
          await FormatResponse().formatSongsResponse(responseList, 'playlist');
    }
    return searchedList;
  }

  Future<List> fetchTopSearchResult(String searchQuery) async {
    final String params = 'p=1&q=$searchQuery&n=10&__call=search.getResults';
    final res = await getResponse(params, useProxy: true);
    if (res.statusCode == 200) {
      final getMain = json.decode(res.body);
      final List responseList = getMain['results'] as List;
      final List searchedList = [
        await FormatResponse().formatSingleSongResponse(responseList[0] as Map)
      ];
      return searchedList;
    }
    return List.empty();
  }

  Future<Map> fetchSongDetails(String songId) async {
    Map result = {};
    final String params = 'pids=$songId&__call=song.getDetails';
    try {
      final res = await getResponse(params);
      if (res.statusCode == 200) {
        final Map data = json.decode(res.body) as Map;
        result = await FormatResponse()
            .formatSingleSongResponse(data['songs'][0] as Map);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in fetchSongDetails: $e');
    }
    return result;
  }
}
