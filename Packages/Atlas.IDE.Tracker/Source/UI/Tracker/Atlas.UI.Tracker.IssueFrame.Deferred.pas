unit Atlas.UI.Tracker.IssueFrame.Deferred;

// Wünsche im Fenster „Atlas-Issue“ (#1264), die erst nach dem auslösenden Klick laufen dürfen: Neuaufbau (ältere
// Kommentare aufklappen), verknüpftes Issue öffnen, Kästchen der Checkliste melden und „Punkt hinzufügen …“ melden
// (#1273). Sie ersetzen den Inhalt samt dem Steuerelement des Klicks; deshalb merken, eine Nachricht an das Fenster
// schicken und in deren Handler mit Run ausführen. Mit dem Fenster verfällt die Nachricht.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.IssueFrame.Contract;

type
  /// <summary>Gemerkte Wünsche bis zur Nachricht AMessage an AWindow; gehört AWindow.</summary>
  TAtlasIssueDeferred = class(TComponent)
  private
    FWindow: TWinControl;
    FMessage: Cardinal;
    FRebuild: Boolean;
    FLink: TAtlasTrackerLink;
    FHasLink: Boolean;
    FTask: Integer;
    FAddTask: Boolean;
    /// <summary>Nachricht schicken; ohne Fenster bleibt der Wunsch bis zur nächsten.</summary>
    procedure Post;
  public
    constructor Create(AWindow: TWinControl; AMessage: Cardinal); reintroduce;
    /// <summary>Inhalt neu aufbauen.</summary>
    procedure Rebuild;
    /// <summary>Verknüpftes Issue öffnen (Events.OpenLink).</summary>
    procedure OpenLink(const ALink: TAtlasTrackerLink);
    /// <summary>Kästchen AIndex der Beschreibung melden (Events.ToggleTask).</summary>
    procedure ToggleTask(AIndex: Integer);
    /// <summary>„Punkt hinzufügen …“ melden (Events.AddTask).</summary>
    procedure AddTask;
    /// <summary>Gemerkte Wünsche ausführen und vergessen: erst ARebuild, dann die Meldungen an AEvents.</summary>
    procedure Run(const AEvents: TAtlasIssueFrameEvents; const ARebuild: TProc);
  end;

implementation

uses
  Winapi.Windows;

{ TAtlasIssueDeferred }

constructor TAtlasIssueDeferred.Create(AWindow: TWinControl; AMessage: Cardinal);
begin
  inherited Create(AWindow);
  FWindow := AWindow;
  FMessage := AMessage;
  FTask := -1;
end;

procedure TAtlasIssueDeferred.Post;
begin
  if FWindow.HandleAllocated then
  begin
    PostMessage(FWindow.Handle, FMessage, 0, 0);
  end;
end;

procedure TAtlasIssueDeferred.Rebuild;
begin
  FRebuild := True;
  Post;
end;

procedure TAtlasIssueDeferred.OpenLink(const ALink: TAtlasTrackerLink);
begin
  FLink := ALink;
  FHasLink := True;
  Post;
end;

procedure TAtlasIssueDeferred.ToggleTask(AIndex: Integer);
begin
  FTask := AIndex;
  Post;
end;

procedure TAtlasIssueDeferred.AddTask;
begin
  FAddTask := True;
  Post;
end;

procedure TAtlasIssueDeferred.Run(const AEvents: TAtlasIssueFrameEvents; const ARebuild: TProc);
var
  mTask: Integer;
begin
  if FRebuild then
  begin
    FRebuild := False;
    ARebuild();
  end;
  if FHasLink then
  begin
    FHasLink := False;
    if Assigned(AEvents.OpenLink) then
    begin
      AEvents.OpenLink(FLink);
    end;
  end;
  mTask := FTask;
  FTask := -1;
  if (mTask >= 0) and Assigned(AEvents.ToggleTask) then
  begin
    AEvents.ToggleTask(mTask);
  end;
  if FAddTask and Assigned(AEvents.AddTask) then
  begin
    AEvents.AddTask();
  end;
  FAddTask := False;
end;

end.
