import 'dart:async';
import 'dart:collection';
import 'package:audioplayer/audioplayer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotify/spotify.dart' hide Image;
import 'package:spotify_manager/common/project_manager/model/project.dart';
import 'package:spotify_manager/common/project_manager/project.dart';
import 'package:spotify_manager/common/project_manager/projects_db.dart';
import 'package:spotify_manager/screens/edit_project.dart';
import 'package:spotify_manager/screens/project_screen.dart';
import 'package:spotify_manager/widgets/floating_bar_list_view.dart';
import 'package:spotify_manager/widgets/search.dart';

class ProjectListView extends StatefulWidget {
  final ProjectConfiguration projectConfig;
  final SpotifyApi api;
  final User me;
  final ProjectsDB db;
  final Project project;

  ProjectListView(
      {@required this.projectConfig,
      @required this.api,
      @required this.me,
      this.project})
      : db = ProjectsDB();

  @override
  _ProjectListViewState createState() => _ProjectListViewState();
}

class _ProjectListViewState extends State<ProjectListView> {
  Future<Project> projectFuture;
  Project project;
  Stream<List<Track>> tracksRevisions;
  ScrollController scrollController;
  AudioPlayer player = new AudioPlayer();
  Queue<String> upNext;
  int nowPlaying;
  int shownTracks = 0;

  @override
  void initState() {
    super.initState();
    setState(() {
      if (widget.project == null)
        projectFuture =
            Project.fromConfiguration(widget.projectConfig, widget.api);
      else
        projectFuture = Future.value(widget.project);
    });
    projectFuture.then((project) async {
      final prefs = await SharedPreferences.getInstance();
      final itemSize = prefs.containsKey(project.uuid)?prefs.getDouble(project.uuid):150.0;
      final screenHeight = MediaQuery.of(context).size.height / 2;
      print(itemSize);
      print(project.curIndex);
      print(itemSize * project.curIndex);
      print((itemSize * project.curIndex) - (screenHeight / 2));
      setState(() {
        print("creating revisions stream");
        tracksRevisions = streamRevisions(project.tracks, batchSize: 50, minCount: project.curIndex + 10);
        this.project = project;
        scrollController = ScrollController(initialScrollOffset: (itemSize * project.curIndex) - (screenHeight / 2));
      });
      return projectFuture;
    });
    player.onPlayerStateChanged.listen((var audioState) {
      if (audioState != AudioPlayerState.COMPLETED || upNext.length <= 0)
        return;
      play(upNext, nowPlaying + 1);
    });
  }

  @override
  void dispose() {
    upNext = Queue<String>();
    player.stop();
    super.dispose();
  }

  play(Iterable<String> _upNext, int index) async {
    upNext = Queue.from(_upNext);
    final track = upNext.removeFirst();
    if (track == null) pause();
    if (player.state != AudioPlayerState.STOPPED) await player.stop();
    await player.play(track);
    setState(() {
      project.curIndex = index;
      nowPlaying = index;
    });
  }

  pause() async {
    await player.pause();
    setState(() {
      nowPlaying = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await setItemSize();
        Navigator.of(context).pop((await projectFuture).curIndex);
        return false;
      },
      child: Scaffold(
        body: StreamBuilder<List<Track>>(
          stream: tracksRevisions,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Icon(Icons.error),
                  ),
                  Text("An error occurred, try again later"),
                  Text(snapshot.error),
                ],
              );
            if (!snapshot.hasData)
              return Center(child: CircularProgressIndicator());
            final tracks = snapshot.data;
            shownTracks = tracks.length;
            final theme = Theme.of(context);
            final conf = widget.projectConfig;
            if (conf.trackIds.length == tracks.length)
              {
                scrollController = ScrollController(initialScrollOffset: scrollController.offset);
                print('setting new controller');
              }
            return FloatingBarListView(
              scrollController: scrollController,
              appBar: SliverAppBar(
                actions: <Widget>[
                  buildProjectToggle(context),
                  buildEditProject(context)
                ],
                floating: true,
                backgroundColor: Theme.of(context).backgroundColor,
                expandedHeight: 150,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  title: Text(project.name, style: theme.textTheme.headline5),
                  centerTitle: true,
                  background: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 70),
                      child: Text(
                        "Sorting ${conf.trackIds.length} tracks to ${conf.playlistIds.length} playlists",
                        style: theme.textTheme.bodyText1,
                      ),
                    ),
                  ),
                ),
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (c, i) {
                if (i == tracks.length)
                  return i == widget.projectConfig.trackIds.length
                      ? Container()
                      : Center(child: CircularProgressIndicator());
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TrackTile(
                      tracks[i],
                      onTap: (track) async {
                        if (nowPlaying == i)
                          await pause();
                        else
                          await play(
                              tracks.sublist(i).map((t) => t.previewUrl), i);
                      },
                      trailing: nowPlaying == i ? Icon(Icons.pause) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Wrap(
                        spacing: 5,
                        children: project.playlists.map<Widget>((playlist) {
                          final selected = playlist.contains(tracks[i]);
                          return ChoiceChip(
                            selectedColor: theme.buttonColor,
                            onSelected: (value) async {
                              if (value)
                                await playlist.addTrack(widget.api, tracks[i]);
                              else
                                await playlist.removeTrack(
                                    widget.api, tracks[i]);
                              setState(() {});
                              project.curIndex = i;
                            },
                            selected: selected,
                            label: Text(playlist.name,
                                style: selected
                                    ? TextStyle(
                                        color: theme.textTheme.button.color,
                                        fontWeight: FontWeight.w500)
                                    : TextStyle(color: Colors.white70)),
                          );
                        }).toList(),
                      ),
                    )
                  ],
                );
              },
              dividerBuilder: (c, i) => Divider(),
            );
          },
        ),
      ),
    );
  }

  Future setItemSize() async {
    final itemSize = scrollController.position.maxScrollExtent / shownTracks;
    print(itemSize);

    print(shownTracks);
    print(project.curIndex);
    print(scrollController.offset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(project.uuid, itemSize);
  }

  void printScrollDebugs(){
    print('scrollController.position.axis.index: ${scrollController.position.axis.index}');
    print('scrollController.position.extentAfter: ${scrollController.position.extentAfter}');
    print('scrollController.position.extentBefore: ${scrollController.position.extentBefore}');
    print('scrollController.position.extentInside: ${scrollController.position.extentInside}');
    print('scrollController.position.viewportDimension: ${scrollController.position.viewportDimension}');
    print('scrollController.position.pixels: ${scrollController.position.pixels}');
    print('scrollController.position.minScrollExtent: ${scrollController.position.minScrollExtent}');
    print('scrollController.position.maxScrollExtent: ${scrollController.position.maxScrollExtent}');
    print('scrollController.position.maxScrollExtent: ${scrollController}');

  IconButton buildEditProject(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.edit),
      onPressed: () async {
        await player.stop();
        widget.projectConfig.curIndex = project.curIndex;
        final config = await project.getConfig(widget.projectConfig.trackIds);
        final edited = await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditProject(
                  widget.api,
                  widget.me,
                  config,
                  onSave: (ctx, newConf) async {
                    Navigator.of(ctx).pop(await Navigator.of(ctx).push(
                        MaterialPageRoute(
                            builder: (_) => ProjectListView(
                                projectConfig: newConf,
                                api: widget.api,
                                me: widget.me))));
                  },
                )));
        if (edited != null){
          Navigator.of(context).pop(edited);
        }
      },
    );
  }

  IconButton buildProjectToggle(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.subscriptions),
      onPressed: () async {
        await player.stop();
        await setItemSize();
        final newCurIndex = await Navigator.of(context)
            .push(MaterialPageRoute(builder: (BuildContext subContext) {
          return ProjectScreen(
            projectConfig: widget.projectConfig..curIndex = project.curIndex,
            client: widget.api,
            me: widget.me,
            project: project,
          );
        }));
        Navigator.of(context).pop(newCurIndex);
      },
    );
  }
}
