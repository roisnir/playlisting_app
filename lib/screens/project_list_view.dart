import 'dart:async';
import 'package:flutter/material.dart';
import 'package:spotify/spotify_io.dart';
import 'package:spotify_manager/common/project_manager/model/project.dart';
import 'package:spotify_manager/common/project_manager/project.dart';
import 'package:spotify_manager/common/project_manager/projects_db.dart';
import 'package:spotify_manager/widgets/floating_bar_list_view.dart';
import 'package:spotify_manager/widgets/search.dart';

class ProjectListView extends StatefulWidget {
  final ProjectConfiguration projectConfig;
  final SpotifyApi api;
  final User me;
  final ProjectsDB db;
  
  ProjectListView({this.projectConfig, this.api, this.me}) : db = ProjectsDB();

  @override
  _ProjectListViewState createState() => _ProjectListViewState();
}

class _ProjectListViewState extends State<ProjectListView> {
  Future<Project> projectFuture;
  Project project;
  Stream<List<Track>> tracksRevisions;
  ScrollController scrollController;
  
  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    setState(() {
      projectFuture = Project.fromConfiguration(widget.projectConfig, widget.api)..then((project) {
        setState(() {
          tracksRevisions = streamRevisions(project.tracks);
          this.project = project;
        });
        return projectFuture;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop((await projectFuture).curIndex);
        return false;
      },
      child: Scaffold(
        body: StreamBuilder<List<Track>>(
          stream: tracksRevisions,
          builder: (context, snapshot) {
            if(snapshot.hasError)
              return Column(children: <Widget>[
                Padding(padding: EdgeInsets.only(bottom: 10), child: Icon(Icons.error),),
                Text("An error occured, try again later"),
                Text(snapshot.error),
              ],);
            if (!snapshot.hasData)
              return Center(child: CircularProgressIndicator());
            final tracks = snapshot.data;
            final theme = Theme.of(context);
            final conf = widget.projectConfig;
            return FloatingBarListView(
              controller: scrollController,
              appBar: SliverAppBar(
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
                      child: Text("Sorting ${conf.trackIds.length} tracks to ${conf.playlistIds.length} playlists", style: theme.textTheme.bodyText1,),
                    ),
                  ),
                ),
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (c, i) {
                if (i == tracks.length)
                  return i == widget.projectConfig.trackIds.length ? Container():
                    Center(child: CircularProgressIndicator());
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TrackTile(tracks[i], onTap: (track){
                      // TODO: add/remove from playlist
                    },),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Wrap(
                        spacing: 5,
                        children: project.playlists.map<Widget>((playlist) =>
                          ChoiceChip(
                            selected: playlist.contains(tracks[i]),
                            label: Text(playlist.name),
                          )).toList(),),
                    )
                  ],
                );
              },
              dividerBuilder: (c, i) => Divider(),);
          },
        ),
      ),
    );
  }
}
