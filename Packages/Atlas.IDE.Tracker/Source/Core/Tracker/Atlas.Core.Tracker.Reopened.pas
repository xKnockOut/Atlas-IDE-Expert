unit Atlas.Core.Tracker.Reopened;

// Wieder geöffnete Issues (#2127), ohne VCL und Open Tools API. Kommt ein
// Issue, das ich beendet habe oder das mir zugewiesen ist, aus einem
// erledigten Zustand oder aus der Prüfung (issues.reviewStates) zurück in
// einen offenen, trägt es in „Meine Issues“ die Marke „wieder offen“ mit dem
// neuesten Kommentar seit dem Beenden und „Weiterarbeiten auf <Branch>“.
// - Erledigt: TAtlasTrackerIssueStates.IsResolvedState (GitHub „closed …“,
//   issues.endStates, übliche englische Namen) oder ein Zustand aus
//   issues.reviewStates (TAtlasTrackerDoneStates).
// - Beenden über Atlas merkt Kennung, Branch, Zeitpunkt und den geschriebenen
//   Zustand (TAtlasTrackerEnded, Abschnitt "issues" der
//   Projekt-Zusammenfassung, "ended"). Zeigt die Liste das Issue später in
//   einem erledigten Zustand, gilt es als erledigt gesehen (Done).
// - Erkennen: aus den Meldungen (#1271, FromNotice: ein fremder
//   Zustandswechsel von erledigt nach offen) oder beim Laden der Liste
//   (FromList: ein erledigt gesehenes, beendetes Issue steht offen in der
//   Liste). Eigene Änderungen melden die Meldungen ohnehin nicht.
// - Die Marke (TAtlasTrackerReopen, "reopened") bleibt bis „Weiterarbeiten“
//   oder „Gelesen“; der Eintrag in "ended" geht mit der Erkennung in die
//   Marke über, damit dieselbe Rückkehr nicht zweimal meldet.
// Je Liste höchstens cMaxEntries Einträge; die ältesten fallen heraus.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify;

type
  /// <summary>Ein mit Atlas beendetes Issue.</summary>
  TAtlasTrackerEnded = record
    Key: string;
    /// <summary>Branch beim Beenden; '' ohne bzw. unbekannt.</summary>
    Branch: string;
    /// <summary>Zeitpunkt des Beendens (UTC).</summary>
    At: TDateTime;
    /// <summary>Beim Beenden geschriebener Zustand; '' = nicht geändert bzw. unbekannt.</summary>
    State: string;
    /// <summary>Erledigt geschrieben oder seitdem erledigt gesehen.</summary>
    Done: Boolean;
  end;

  /// <summary>Marke „wieder offen“ an einem Issue.</summary>
  TAtlasTrackerReopen = record
    Key: string;
    Title: string;
    /// <summary>Zustand jetzt und davor; '' unbekannt.</summary>
    State: string;
    Previous: string;
    /// <summary>Zeitpunkt der Rückkehr bzw. der Erkennung (UTC).</summary>
    At: TDateTime;
    /// <summary>Beendet am (UTC); 0 = nicht mit Atlas beendet. Kommentare danach sind der Grund.</summary>
    EndedAt: TDateTime;
    /// <summary>Branch aus dem Beenden; '' = nach dem Muster.</summary>
    Branch: string;
    /// <summary>Neuester Kommentar seit dem Beenden: Urheber, Zeitpunkt (UTC), Text gekürzt; '' bzw. 0 ohne.
    /// </summary>
    CommentBy: string;
    CommentAt: TDateTime;
    Comment: string;
  end;

  /// <summary>Was als erledigt gilt.</summary>
  TAtlasTrackerDoneStates = record
    Provider: string;
    /// <summary>issues.endStates (je Verbindung überschreibbar).</summary>
    EndStates: TArray<string>;
    /// <summary>issues.reviewStates (je Verbindung überschreibbar).</summary>
    ReviewStates: TArray<string>;
    class function Create(const AProvider: string; const AEndStates, AReviewStates: TArray<string>):
      TAtlasTrackerDoneStates; static;
    /// <summary>AState ist erledigt oder ein Prüfzustand.</summary>
    function IsDone(const AState: string): Boolean;
    /// <summary>AState steht in ReviewStates (ohne Groß-/Kleinschreibung).</summary>
    function IsReview(const AState: string): Boolean;
  end;

  TAtlasTrackerReopened = class
  public const
    /// <summary>Höchstens so viele beendete Issues und Marken je Projekt.</summary>
    cMaxEntries = 20;
    /// <summary>Höchstlänge des Kommentars an der Marke.</summary>
    cMaxComment = 200;
    cEndedName = 'ended';
    cReopenedName = 'reopened';
  public
    /// <summary>Text für die Marke: Zeilenumbrüche zu Leerzeichen, höchstens cMaxComment Zeichen.</summary>
    class function Shortened(const AText: string): string; static;
    /// <summary>Von APrevious (erledigt bzw. Prüfung) nach AState (offen)?</summary>
    class function IsReopen(const ADone: TAtlasTrackerDoneStates; const APrevious, AState: string): Boolean; static;
    /// <summary>Betrifft mich: mit Atlas beendet (AEnded) oder in der Liste „Meine Issues“ (AItems).</summary>
    class function Concerns(const AEnded: TArray<TAtlasTrackerEnded>; const AItems: TArray<TAtlasTrackerIssue>;
      const AKey: string): Boolean; static;
    /// <summary>Marke aus einer Meldung (#1271); False, wenn sie keine Rückkehr zu offen enthält.</summary>
    class function FromNotice(const ADone: TAtlasTrackerDoneStates; const ANotice: TAtlasTrackerNotice;
      out AReopen: TAtlasTrackerReopen): Boolean; static;
    /// <summary>Beim Laden der Liste: AEnded erledigt sehen (Done) und Marken für erledigt gesehene, die jetzt offen
    /// in AItems stehen; deren Einträge verlassen AEnded.</summary>
    class function FromList(const ADone: TAtlasTrackerDoneStates; var AEnded: TArray<TAtlasTrackerEnded>;
      const AItems: TArray<TAtlasTrackerIssue>; ANowUtc: TDateTime): TArray<TAtlasTrackerReopen>; static;
    /// <summary>Branch und Zeitpunkt des Beendens an AReopen; der Eintrag verlässt AEnded.</summary>
    class procedure TakeEnded(var AEnded: TArray<TAtlasTrackerEnded>; var AReopen: TAtlasTrackerReopen); static;
    /// <summary>Beenden merken: ersetzt einen Eintrag derselben Kennung, die ältesten fallen heraus.</summary>
    class procedure AddEnded(var AEnded: TArray<TAtlasTrackerEnded>; const AEntry: TAtlasTrackerEnded); static;
    class function IndexOfEnded(const AEnded: TArray<TAtlasTrackerEnded>; const AKey: string): Integer; static;
    /// <summary>Marke setzen: ersetzt eine derselben Kennung (ein Kommentar der alten bleibt, wenn die neue keinen
    /// hat); die ältesten fallen heraus.</summary>
    class procedure Mark(var AReopened: TArray<TAtlasTrackerReopen>; const AReopen: TAtlasTrackerReopen); static;
    class function IndexOf(const AReopened: TArray<TAtlasTrackerReopen>; const AKey: string): Integer; static;
    class function Find(const AReopened: TArray<TAtlasTrackerReopen>; const AKey: string;
      out AReopen: TAtlasTrackerReopen): Boolean; static;
    /// <summary>„Weiterarbeiten“ oder „Gelesen“: Marke entfernen; True, wenn es eine gab.</summary>
    class function Dismiss(var AReopened: TArray<TAtlasTrackerReopen>; const AKey: string): Boolean; static;
    /// <summary>Neuester Kommentar nach ASince (UTC), nicht von AMe (Urheber ohne Groß-/Kleinschreibung); False
    /// ohne.</summary>
    class function LatestComment(const AComments: TArray<TAtlasTrackerComment>; ASince: TDateTime;
      const AMe: string; out AComment: TAtlasTrackerComment): Boolean; static;
    /// <summary>AComment als Grund an AReopen, wenn er neuer ist als der bisherige.</summary>
    class procedure TakeComment(var AReopen: TAtlasTrackerReopen; const AComment: TAtlasTrackerComment); static;
    /// <summary>"ended" und "reopened" in ASection schreiben (leere Listen entfallen).</summary>
    class procedure WriteJson(ASection: TJSONObject; const AEnded: TArray<TAtlasTrackerEnded>;
      const AReopened: TArray<TAtlasTrackerReopen>); static;
    /// <summary>"ended" und "reopened" aus ASection; Einträge ohne Kennung entfallen.</summary>
    class procedure ReadJson(ASection: TJSONObject; out AEnded: TArray<TAtlasTrackerEnded>;
      out AReopened: TArray<TAtlasTrackerReopen>); static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Tracker.IssueWork,
  Atlas.Text.Json;

{ TAtlasTrackerDoneStates }

class function TAtlasTrackerDoneStates.Create(const AProvider: string; const AEndStates,
  AReviewStates: TArray<string>): TAtlasTrackerDoneStates;
begin
  Result.Provider := AProvider;
  Result.EndStates := Copy(AEndStates);
  Result.ReviewStates := Copy(AReviewStates);
end;

function TAtlasTrackerDoneStates.IsReview(const AState: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if Trim(AState) = '' then
  begin
    Exit;
  end;
  for mName in ReviewStates do
  begin
    if SameText(Trim(mName), Trim(AState)) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasTrackerDoneStates.IsDone(const AState: string): Boolean;
begin
  Result := IsReview(AState) or TAtlasTrackerIssueStates.IsResolvedState(Provider, AState, EndStates);
end;

{ TAtlasTrackerReopened }

class function TAtlasTrackerReopened.Shortened(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > cMaxComment then
  begin
    Result := Copy(Result, 1, cMaxComment - 1) + '…';
  end;
end;

class function TAtlasTrackerReopened.IsReopen(const ADone: TAtlasTrackerDoneStates;
  const APrevious, AState: string): Boolean;
begin
  Result := (Trim(AState) <> '') and ADone.IsDone(APrevious) and not ADone.IsDone(AState);
end;

class function TAtlasTrackerReopened.IndexOfEnded(const AEnded: TArray<TAtlasTrackerEnded>;
  const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AEnded) do
  begin
    if SameText(AEnded[mIndex].Key, AKey) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTrackerReopened.Concerns(const AEnded: TArray<TAtlasTrackerEnded>;
  const AItems: TArray<TAtlasTrackerIssue>; const AKey: string): Boolean;
var
  mItem: TAtlasTrackerIssue;
begin
  Result := IndexOfEnded(AEnded, AKey) >= 0;
  if Result then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if SameText(mItem.Key, AKey) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTrackerReopened.FromNotice(const ADone: TAtlasTrackerDoneStates;
  const ANotice: TAtlasTrackerNotice; out AReopen: TAtlasTrackerReopen): Boolean;
begin
  AReopen := Default(TAtlasTrackerReopen);
  Result := ANotice.StateChanged and IsReopen(ADone, ANotice.Previous, ANotice.State);
  if not Result then
  begin
    Exit;
  end;
  AReopen.Key := ANotice.Key;
  AReopen.Title := ANotice.Title;
  AReopen.State := ANotice.State;
  AReopen.Previous := ANotice.Previous;
  AReopen.At := ANotice.Time;
  AReopen.CommentBy := ANotice.LastCommentBy;
  AReopen.CommentAt := ANotice.LastCommentAt;
  AReopen.Comment := TAtlasTrackerReopened.Shortened(ANotice.LastComment);
end;

class procedure TAtlasTrackerReopened.TakeEnded(var AEnded: TArray<TAtlasTrackerEnded>;
  var AReopen: TAtlasTrackerReopen);
var
  mIndex: Integer;
begin
  mIndex := IndexOfEnded(AEnded, AReopen.Key);
  if mIndex < 0 then
  begin
    Exit;
  end;
  AReopen.Branch := AEnded[mIndex].Branch;
  AReopen.EndedAt := AEnded[mIndex].At;
  if AReopen.Previous = '' then
  begin
    AReopen.Previous := AEnded[mIndex].State;
  end;
  // Ein Kommentar vor dem Beenden ist nicht der Grund der Rückkehr.
  if (AReopen.CommentAt > 0) and (AReopen.CommentAt <= AReopen.EndedAt) then
  begin
    AReopen.CommentBy := '';
    AReopen.CommentAt := 0;
    AReopen.Comment := '';
  end;
  Delete(AEnded, mIndex, 1);
end;

/// <summary>Eintrag von AKey in AItems; False ohne.</summary>
function FindItem(const AItems: TArray<TAtlasTrackerIssue>; const AKey: string; out AItem: TAtlasTrackerIssue):
  Boolean;
var
  mItem: TAtlasTrackerIssue;
begin
  for mItem in AItems do
  begin
    if SameText(mItem.Key, AKey) then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := TAtlasTrackerIssue.Empty;
  Result := False;
end;

class function TAtlasTrackerReopened.FromList(const ADone: TAtlasTrackerDoneStates;
  var AEnded: TArray<TAtlasTrackerEnded>; const AItems: TArray<TAtlasTrackerIssue>;
  ANowUtc: TDateTime): TArray<TAtlasTrackerReopen>;
var
  mIndex: Integer;
  mItem: TAtlasTrackerIssue;
  mReopen: TAtlasTrackerReopen;
begin
  Result := nil;
  // Rückwärts: TakeEnded entfernt den Eintrag.
  for mIndex := High(AEnded) downto 0 do
  begin
    if not FindItem(AItems, AEnded[mIndex].Key, mItem) or (Trim(mItem.State) = '') then
    begin
      Continue;
    end;
    if ADone.IsDone(mItem.State) then
    begin
      AEnded[mIndex].Done := True;
      Continue;
    end;
    if not AEnded[mIndex].Done then
    begin
      Continue;
    end;
    mReopen := Default(TAtlasTrackerReopen);
    mReopen.Key := mItem.Key;
    mReopen.Title := mItem.Title;
    mReopen.State := mItem.State;
    mReopen.At := ANowUtc;
    TakeEnded(AEnded, mReopen);
    Result := Result + [mReopen];
  end;
end;

class procedure TAtlasTrackerReopened.AddEnded(var AEnded: TArray<TAtlasTrackerEnded>;
  const AEntry: TAtlasTrackerEnded);
var
  mIndex: Integer;
begin
  if Trim(AEntry.Key) = '' then
  begin
    Exit;
  end;
  mIndex := IndexOfEnded(AEnded, AEntry.Key);
  if mIndex >= 0 then
  begin
    Delete(AEnded, mIndex, 1);
  end;
  AEnded := AEnded + [AEntry];
  if Length(AEnded) > cMaxEntries then
  begin
    AEnded := Copy(AEnded, Length(AEnded) - cMaxEntries, cMaxEntries);
  end;
end;

class function TAtlasTrackerReopened.IndexOf(const AReopened: TArray<TAtlasTrackerReopen>;
  const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AReopened) do
  begin
    if SameText(AReopened[mIndex].Key, AKey) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTrackerReopened.Find(const AReopened: TArray<TAtlasTrackerReopen>; const AKey: string;
  out AReopen: TAtlasTrackerReopen): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AReopened, AKey);
  Result := mIndex >= 0;
  if Result then
  begin
    AReopen := AReopened[mIndex];
  end
  else
  begin
    AReopen := Default(TAtlasTrackerReopen);
  end;
end;

class procedure TAtlasTrackerReopened.Mark(var AReopened: TArray<TAtlasTrackerReopen>;
  const AReopen: TAtlasTrackerReopen);
var
  mIndex: Integer;
  mReopen: TAtlasTrackerReopen;
begin
  if Trim(AReopen.Key) = '' then
  begin
    Exit;
  end;
  mReopen := AReopen;
  mIndex := IndexOf(AReopened, AReopen.Key);
  if mIndex >= 0 then
  begin
    // Branch und Grund der früheren Erkennung gehen nicht verloren.
    if mReopen.Branch = '' then
    begin
      mReopen.Branch := AReopened[mIndex].Branch;
      mReopen.EndedAt := AReopened[mIndex].EndedAt;
    end;
    if mReopen.CommentAt < AReopened[mIndex].CommentAt then
    begin
      mReopen.CommentBy := AReopened[mIndex].CommentBy;
      mReopen.CommentAt := AReopened[mIndex].CommentAt;
      mReopen.Comment := AReopened[mIndex].Comment;
    end;
    Delete(AReopened, mIndex, 1);
  end;
  AReopened := AReopened + [mReopen];
  if Length(AReopened) > cMaxEntries then
  begin
    AReopened := Copy(AReopened, Length(AReopened) - cMaxEntries, cMaxEntries);
  end;
end;

class function TAtlasTrackerReopened.Dismiss(var AReopened: TArray<TAtlasTrackerReopen>;
  const AKey: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AReopened, AKey);
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(AReopened, mIndex, 1);
  end;
end;

class function TAtlasTrackerReopened.LatestComment(const AComments: TArray<TAtlasTrackerComment>;
  ASince: TDateTime; const AMe: string; out AComment: TAtlasTrackerComment): Boolean;
var
  mComment: TAtlasTrackerComment;
begin
  AComment := Default(TAtlasTrackerComment);
  Result := False;
  for mComment in AComments do
  begin
    if (mComment.Created > ASince) and ((AMe = '') or not SameText(mComment.Author, AMe)) and
      (not Result or (mComment.Created >= AComment.Created)) then
    begin
      AComment := mComment;
      Result := True;
    end;
  end;
end;

class procedure TAtlasTrackerReopened.TakeComment(var AReopen: TAtlasTrackerReopen;
  const AComment: TAtlasTrackerComment);
begin
  if (AComment.Created <= AReopen.CommentAt) or (Trim(AComment.Text) = '') then
  begin
    Exit;
  end;
  AReopen.CommentBy := AComment.Author;
  AReopen.CommentAt := AComment.Created;
  AReopen.Comment := TAtlasTrackerReopened.Shortened(AComment.Text);
end;

function IsoOf(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
  begin
    Result := DateToISO8601(AValue, True);
  end;
end;

function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  mText := TJsonRead.Text(AObject, AName);
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
  begin
    Result := 0;
  end;
end;

/// <summary>Feld nur mit Inhalt schreiben.</summary>
procedure AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

function EndedJson(const AEntry: TAtlasTrackerEnded): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('key', AEntry.Key);
  AddText(Result, 'branch', AEntry.Branch);
  AddText(Result, 'at', IsoOf(AEntry.At));
  AddText(Result, 'state', AEntry.State);
  if AEntry.Done then
  begin
    Result.AddPair('done', TJSONBool.Create(True));
  end;
end;

function ReopenJson(const AReopen: TAtlasTrackerReopen): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('key', AReopen.Key);
  AddText(Result, 'title', AReopen.Title);
  AddText(Result, 'state', AReopen.State);
  AddText(Result, 'previous', AReopen.Previous);
  AddText(Result, 'at', IsoOf(AReopen.At));
  AddText(Result, 'endedAt', IsoOf(AReopen.EndedAt));
  AddText(Result, 'branch', AReopen.Branch);
  AddText(Result, 'commentBy', AReopen.CommentBy);
  AddText(Result, 'commentAt', IsoOf(AReopen.CommentAt));
  AddText(Result, 'comment', AReopen.Comment);
end;

class procedure TAtlasTrackerReopened.WriteJson(ASection: TJSONObject; const AEnded: TArray<TAtlasTrackerEnded>;
  const AReopened: TArray<TAtlasTrackerReopen>);
var
  mList: TJSONArray;
  mEnded: TAtlasTrackerEnded;
  mReopen: TAtlasTrackerReopen;
begin
  if Length(AEnded) > 0 then
  begin
    mList := TJSONArray.Create;
    ASection.AddPair(cEndedName, mList);
    for mEnded in AEnded do
    begin
      mList.AddElement(EndedJson(mEnded));
    end;
  end;
  if Length(AReopened) > 0 then
  begin
    mList := TJSONArray.Create;
    ASection.AddPair(cReopenedName, mList);
    for mReopen in AReopened do
    begin
      mList.AddElement(ReopenJson(mReopen));
    end;
  end;
end;

function EndedOf(AObject: TJSONObject): TAtlasTrackerEnded;
begin
  Result := Default(TAtlasTrackerEnded);
  Result.Key := Trim(TJsonRead.Text(AObject, 'key'));
  Result.Branch := TJsonRead.Text(AObject, 'branch');
  Result.At := TimeOf(AObject, 'at');
  Result.State := TJsonRead.Text(AObject, 'state');
  Result.Done := TJsonRead.Flag(AObject, 'done');
end;

function ReopenOf(AObject: TJSONObject): TAtlasTrackerReopen;
begin
  Result := Default(TAtlasTrackerReopen);
  Result.Key := Trim(TJsonRead.Text(AObject, 'key'));
  Result.Title := TJsonRead.Text(AObject, 'title');
  Result.State := TJsonRead.Text(AObject, 'state');
  Result.Previous := TJsonRead.Text(AObject, 'previous');
  Result.At := TimeOf(AObject, 'at');
  Result.EndedAt := TimeOf(AObject, 'endedAt');
  Result.Branch := TJsonRead.Text(AObject, 'branch');
  Result.CommentBy := TJsonRead.Text(AObject, 'commentBy');
  Result.CommentAt := TimeOf(AObject, 'commentAt');
  Result.Comment := TJsonRead.Text(AObject, 'comment');
end;

/// <summary>Beendete Einträge aus der Liste AList (ohne Kennung übersprungen).</summary>
function EndedListOf(AList: TJSONValue): TArray<TAtlasTrackerEnded>;
var
  mItem: TJSONValue;
  mEnded: TAtlasTrackerEnded;
begin
  Result := nil;
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AList) do
  begin
    if mItem is TJSONObject then
    begin
      mEnded := EndedOf(TJSONObject(mItem));
      if mEnded.Key <> '' then
      begin
        TAtlasTrackerReopened.AddEnded(Result, mEnded);
      end;
    end;
  end;
end;

/// <summary>Marken „wieder offen“ aus der Liste AList.</summary>
function ReopenListOf(AList: TJSONValue): TArray<TAtlasTrackerReopen>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AList) do
  begin
    if mItem is TJSONObject then
    begin
      TAtlasTrackerReopened.Mark(Result, ReopenOf(TJSONObject(mItem)));
    end;
  end;
end;

class procedure TAtlasTrackerReopened.ReadJson(ASection: TJSONObject; out AEnded: TArray<TAtlasTrackerEnded>;
  out AReopened: TArray<TAtlasTrackerReopen>);
begin
  AEnded := nil;
  AReopened := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  AEnded := EndedListOf(ASection.Values[cEndedName]);
  AReopened := ReopenListOf(ASection.Values[cReopenedName]);
end;

end.
