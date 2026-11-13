unit Atlas.IDE.Tracker.IssueComments;

// Kommentar im Fenster „Atlas-Issue“:
// - Tracker nachführen (#1266): Mit issues.syncState und einem Tracker, der
//   schreiben kann (Hook CanWrite), gibt es unten „Kommentar schreiben …“
//   (Strg+Enter sendet, danach wird das Issue neu geladen) und für das
//   aktuelle Issue (Hook IsActive) den Knopf „Beenden …“.
// - Kommentar-Editor (#1278): Das Kommentarfeld wird je gezeigtem Issue an
//   Hook CommentAssist gebunden (Vorschläge, Textbausteine, Entwurf des Felds
//   "preview"); beim Wechsel des Issues bleibt der Entwurf gespeichert und das
//   Feld wird leer. Kommt das Senden zurück, wenn schon ein anderes Issue
//   gezeigt wird, löscht Hook CommentSent den Entwurf des gesendeten.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.UI.Tracker.IssueFrame.Contract,
  Atlas.UI.Tracker.EndDialog,
  Atlas.IDE.Tracker.IssueContext;

type
  /// <summary>Kommentar zu AKey schreiben (#1266); ADone im Hauptthread, genau einmal.</summary>
  TAtlasIssuePreviewCommentHook = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const AKey, AText: string; const ADone: TAtlasTrackerSendDone);
  /// <summary>Kommentar-Editor für das Kommentarfeld zu AKey (#1278); nil mit issues.commentEditor aus.</summary>
  TAtlasIssuePreviewAssistHook = reference to function(const ATarget: TAtlasTrackerTarget;
    const AKey: string): IAtlasCommentAssist;
  TAtlasIssuePreviewSentHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string);

  /// <summary>Hooks des Kommentarfelds.</summary>
  TAtlasIssueCommentHooks = record
    /// <summary>issues.syncState an und der Tracker kann schreiben (#1266).</summary>
    CanWrite: TFunc<TAtlasTrackerTarget, Boolean>;
    /// <summary>Die Kennung ist das aktuelle Issue (#1266).</summary>
    IsActive: TFunc<string, Boolean>;
    Comment: TAtlasIssuePreviewCommentHook;
    CommentAssist: TAtlasIssuePreviewAssistHook;
    /// <summary>Kommentar zu AKey gesendet, das Feld zeigt schon ein anderes Issue: dessen Entwurf löschen.
    /// </summary>
    CommentSent: TAtlasIssuePreviewSentHook;
  end;

  TAtlasIdeIssueComments = class
  private
    FContext: TAtlasIdeIssueContext;
    FHooks: TAtlasIssueCommentHooks;
    /// <summary>Das gezeigte Issue neu laden.</summary>
    FRefresh: TProc;
    /// <summary>Tracker und Kennung, an die das Kommentarfeld gebunden ist; '' = ungebunden.</summary>
    FBoundKey: string;
    FBoundActive: Boolean;
  public
    constructor Create(AContext: TAtlasIdeIssueContext; const AHooks: TAtlasIssueCommentHooks;
      const ARefresh: TProc);
    destructor Destroy; override;
    /// <summary>Kommentarfeld und „Beenden …“ nach issues.syncState und dem aktuellen Issue.</summary>
    procedure UpdateWrite;
    /// <summary>Neues Fenster: das Kommentarfeld ist noch nicht gebunden.</summary>
    procedure Unbind;
    /// <summary>AText als Kommentar zum gezeigten Issue senden.</summary>
    procedure Send(const AText: string);
    /// <summary>Abgemeldet: keine Hooks mehr.</summary>
    procedure Stop;
  end;

implementation

uses
  Atlas.UI.Tracker.IssueFrame,
  Atlas.Core.Tracker.Preview,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tracker.CommentEditor;

/// <summary>Kommentarfeld an das gezeigte Issue binden (#1278).</summary>
procedure BindComment(AOwner: TAtlasIdeIssueComments; AFrame: TAtlasIssueFrame; AWrite: Boolean);
var
  mKey: string;
  mActive: Boolean;
  mAssist: IAtlasCommentAssist;
  mEditor: TAtlasCommentEditor;
  mCurrent: TAtlasIssueHistoryEntry;
begin
  mCurrent := AOwner.FContext.Current;
  mKey := '';
  if AWrite then
  begin
    mKey := TAtlasCommentDrafts.TrackerKey(mCurrent.Target) + '|' + mCurrent.Key;
  end;
  mActive := TAtlasIdeSettings.Current.IssuesCommentEditor;
  // Dasselbe Issue mit derselben Einstellung: die Bindung (und der getippte Text) bleibt.
  if SameText(mKey, AOwner.FBoundKey) and (mActive = AOwner.FBoundActive) then
  begin
    Exit;
  end;
  mEditor := AFrame.Parts.Comment;
  // Der Entwurf des bisherigen Issues bleibt gespeichert; das Feld beginnt leer. Ohne Bindung (Editor aus)
  // bleibt der Text wie bisher stehen.
  if mEditor.Assist <> nil then
  begin
    mEditor.Unbind;
    mEditor.SetText('');
  end;
  AOwner.FBoundKey := mKey;
  AOwner.FBoundActive := mActive;
  mAssist := nil;
  if (mKey <> '') and mActive and Assigned(AOwner.FHooks.CommentAssist) then
  begin
    mAssist := AOwner.FHooks.CommentAssist(mCurrent.Target, mCurrent.Key);
  end;
  mEditor.Enhanced := mAssist <> nil;
  mEditor.Bind(mAssist);
end;

/// <summary>Senden ist zurück (Hauptthread): Feld, Entwurf und Neuladen.</summary>
procedure CommentSent(AOwner: TAtlasIdeIssueComments; const ATarget: TAtlasTrackerTarget; const AKey: string;
  const AResult: TAtlasTrackerWriteResult);
var
  mFrame: TAtlasIssueFrame;
  mSame: Boolean;
begin
  mFrame := AOwner.FContext.Frame;
  mSame := AOwner.FContext.HasCurrent and SameText(AOwner.FContext.Current.Key, AKey);
  // Zeigt das Feld inzwischen ein anderes Issue, gehört sein Text nicht zum gesendeten Kommentar.
  if mSame and (mFrame <> nil) then
  begin
    mFrame.CommentDone(TAtlasTrackerEndDialog.ErrorText(AKey, AResult));
  end
  else if mFrame <> nil then
  begin
    mFrame.SetFlag(TAtlasIssueFlag.CommentSending, False);
  end;
  if not mSame and AResult.Succeeded and Assigned(AOwner.FHooks.CommentSent) then
  begin
    AOwner.FHooks.CommentSent(ATarget, AKey);
  end;
  // Den neuen Kommentar zeigen: dasselbe Issue neu laden.
  if AResult.Succeeded and mSame then
  begin
    AOwner.FRefresh();
  end;
end;

{ TAtlasIdeIssueComments }

constructor TAtlasIdeIssueComments.Create(AContext: TAtlasIdeIssueContext; const AHooks: TAtlasIssueCommentHooks;
  const ARefresh: TProc);
begin
  inherited Create;
  FContext := AContext;
  FHooks := AHooks;
  FRefresh := ARefresh;
end;

destructor TAtlasIdeIssueComments.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasIdeIssueComments.Stop;
begin
  FHooks := Default(TAtlasIssueCommentHooks);
  FRefresh := nil;
end;

procedure TAtlasIdeIssueComments.Unbind;
begin
  FBoundKey := '';
  FBoundActive := False;
end;

procedure TAtlasIdeIssueComments.UpdateWrite;
var
  mFrame: TAtlasIssueFrame;
  mWrite: Boolean;
begin
  mFrame := FContext.Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mWrite := FContext.Started and FContext.HasCurrent and Assigned(FHooks.CanWrite);
  mWrite := mWrite and FHooks.CanWrite(FContext.Current.Target);
  mFrame.SetFlag(TAtlasIssueFlag.CanWrite, mWrite);
  mFrame.SetFlag(TAtlasIssueFlag.CanEnd, mWrite and Assigned(FHooks.IsActive) and
    FHooks.IsActive(FContext.Current.Key));
  BindComment(Self, mFrame, mWrite);
end;

procedure TAtlasIdeIssueComments.Send(const AText: string);
var
  mFrame: TAtlasIssueFrame;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueComments;
  mKey: string;
  mTarget: TAtlasTrackerTarget;
begin
  mFrame := FContext.Frame;
  if (mFrame = nil) or not FContext.Started or not FContext.HasCurrent or not Assigned(FHooks.Comment) then
  begin
    Exit;
  end;
  mKeep := FContext.Keep;
  mOwner := Self;
  mKey := FContext.Current.Key;
  mTarget := FContext.Current.Target;
  mFrame.SetFlag(TAtlasIssueFlag.CommentSending, True);
  FHooks.Comment(mTarget, mKey, AText,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      if (mKeep <> nil) and mOwner.FContext.Started then
      begin
        CommentSent(mOwner, mTarget, mKey, AResult);
      end;
    end);
end;

end.
