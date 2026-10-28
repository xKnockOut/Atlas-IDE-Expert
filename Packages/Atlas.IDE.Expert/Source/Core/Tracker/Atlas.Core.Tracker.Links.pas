unit Atlas.Core.Tracker.Links;

// Abhängigkeiten und Unteraufgaben eines Issues (#1279), ohne VCL und Open
// Tools API, damit alles ohne Fenster und ohne Server testbar ist:
// - YouTrackKind: Art eines YouTrack-Links aus Linktyp und Richtung. Erkannt
//   am Namen (englisch und deutsch: Depend/Abhängigkeit, Subtask/
//   Unteraufgabe, Duplicate/Duplikat, Relates/Bezieht sich auf), an
//   „aggregation“ (Eltern-Kind-Typ) oder an den Beschriftungen („depends on“,
//   „hängt ab von“, „is required for“, „ist erforderlich für“ …). Richtung
//   OUTWARD = das gezeigte Issue ist die Quelle (sourceToTarget), INWARD = das
//   Ziel; Typen mit vertauschten Beschriftungen werden umgedreht.
// - Groups: der Baum der Vorschau in fester Reihenfolge (hängt ab von,
//   blockiert, Unteraufgaben, übergeordnet, Duplikat von, dupliziert durch,
//   bezieht sich auf, erwähnt in, Pull Requests, sonstige); Duplikate,
//   „bezieht sich auf“ und Erwähnungen eingeklappt.
// - Progress: erledigte und alle Unteraufgaben („2/3“).
// - OpenBlockers, WarnOnStart: offene „hängt ab von“-Issues; Grundlage der
//   Warnung beim Beginnen (issues.warnBlocked) und des Schlosses auf der
//   Board-Karte (Locked, #1272). Ein Issue mit unbekanntem Zustand warnt nicht.
// - TextDependencies: GitHub ohne „blocked by“-Beziehungen; Nummern aus
//   „depends on #12“, „blocked by #12“, „hängt ab von #12“ im Text bzw. am
//   Zeilenanfang „Benötigt: #12, #13“ (wie in den Issues von Atlas selbst).

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Symbol einer Zeile im Baum: Zustand unbekannt, offen, erledigt bzw. offen und blockiert das gezeigte
  /// Issue.</summary>
  TAtlasTrackerLinkMark = (Unknown, Open, Done, Blocking);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Gruppe des Baums.</summary>
  TAtlasTrackerLinkGroup = record
    Kind: TAtlasTrackerLinkKind;
    Links: TArray<TAtlasTrackerLink>;
    /// <summary>Anfangs eingeklappt (Duplikate, „bezieht sich auf“, Erwähnungen, Pull Requests, sonstige).
    /// </summary>
    Collapsed: Boolean;
    /// <summary>Erledigte bzw. alle Einträge der Gruppe (Fortschritt der Unteraufgaben).</summary>
    Done: Integer;
    Total: Integer;
  end;

  TAtlasTrackerLinks = class
  public const
    /// <summary>Höchstens so viele Nummern liest TextDependencies.</summary>
    MaxTextDependencies = 10;
  public
    /// <summary>Art eines YouTrack-Links. AName: Name des Linktyps (auch lokalisiert), ASourceToTarget/
    /// ATargetToSource: Beschriftungen, ADirection: OUTWARD, INWARD oder BOTH, AAggregation: Eltern-Kind-Typ.
    /// </summary>
    class function YouTrackKind(const AName, ASourceToTarget, ATargetToSource, ADirection: string;
      AAggregation: Boolean): TAtlasTrackerLinkKind; static;
    /// <summary>Gruppen in fester Reihenfolge; leere Gruppen entfallen. Innerhalb einer Gruppe bleibt die
    /// Reihenfolge des Trackers.</summary>
    class function Groups(const ALinks: TArray<TAtlasTrackerLink>): TArray<TAtlasTrackerLinkGroup>; static;
    /// <summary>Gruppe der Art AKind anfangs eingeklappt?</summary>
    class function Collapsed(AKind: TAtlasTrackerLinkKind): Boolean; static;
    /// <summary>Unteraufgaben: ADone erledigt von ATotal. False ohne Unteraufgaben.</summary>
    class function Progress(const ALinks: TArray<TAtlasTrackerLink>; out ADone, ATotal: Integer): Boolean; static;
    /// <summary>"2/3".</summary>
    class function ProgressText(ADone, ATotal: Integer): string; static;
    /// <summary>Offene „hängt ab von“-Issues (Zustand bekannt, nicht erledigt).</summary>
    class function OpenBlockers(const ALinks: TArray<TAtlasTrackerLink>): TArray<TAtlasTrackerLink>; static;
    /// <summary>Warnung beim Beginnen: die offenen Blocker, wenn AWarn (issues.warnBlocked); sonst keine.</summary>
    class function WarnOnStart(AWarn: Boolean; const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerLink>;
      static;
    /// <summary>Karte im Board (#1272) bekommt ein Schloss: mindestens ein offenes „hängt ab von“.</summary>
    class function Locked(const ADetails: TAtlasTrackerDetails): Boolean; static;
    /// <summary>Symbol der Zeile.</summary>
    class function Mark(const ALink: TAtlasTrackerLink): TAtlasTrackerLinkMark; static;
    /// <summary>Nummern abhängiger Issues aus dem Text (siehe Kopf der Unit), ohne Doppelte, höchstens
    /// MaxTextDependencies.</summary>
    class function TextDependencies(const AText: string): TArray<Integer>; static;
  end;

implementation

uses
  System.StrUtils;

type
{$SCOPEDENUMS ON}
  TFamily = (None, Depend, Subtask, Duplicate, Relates);
{$SCOPEDENUMS OFF}

const
  // Reihenfolge der Gruppen im Baum.
  GroupOrder: array[0..9] of TAtlasTrackerLinkKind = (TAtlasTrackerLinkKind.DependsOn,
    TAtlasTrackerLinkKind.Blocks, TAtlasTrackerLinkKind.Subtask, TAtlasTrackerLinkKind.Parent,
    TAtlasTrackerLinkKind.Duplicates, TAtlasTrackerLinkKind.DuplicatedBy, TAtlasTrackerLinkKind.Relates,
    TAtlasTrackerLinkKind.Mentioned, TAtlasTrackerLinkKind.PullRequest, TAtlasTrackerLinkKind.Other);
  // Namen der Linktypen (englische Vorgaben von YouTrack, deutsche Oberfläche, verbreitete eigene Typen).
  DependNames: array[0..6] of string = ('Depend', 'Depends', 'Dependency', 'Abhängigkeit', 'Blocks', 'Block',
    'Blockiert');
  SubtaskNames: array[0..3] of string = ('Subtask', 'Sub-task', 'Unteraufgabe', 'Parent-Child');
  DuplicateNames: array[0..2] of string = ('Duplicate', 'Duplikat', 'Duplicates');
  RelatesNames: array[0..4] of string = ('Relates', 'Relate', 'Bezieht sich auf', 'Verwandt', 'Relation');
  // Beschriftungen auf der Seite der Quelle (sourceToTarget) bzw. des Ziels (targetToSource).
  DependSource: array[0..4] of string = ('is required for', 'ist erforderlich für', 'wird benötigt von', 'blocks',
    'blockiert');
  DependTarget: array[0..5] of string = ('depends on', 'hängt ab von', 'ist abhängig von', 'is blocked by',
    'wird blockiert von', 'wird blockiert durch');
  SubtaskSource: array[0..4] of string = ('parent for', 'übergeordnet zu', 'übergeordnet für',
    'ist übergeordnet zu', 'Elternteil von');
  SubtaskTarget: array[0..2] of string = ('subtask of', 'Unteraufgabe von', 'ist Unteraufgabe von');
  DuplicateSource: array[0..3] of string = ('is duplicated by', 'wird dupliziert durch', 'wird dupliziert von',
    'hat Duplikat');
  DuplicateTarget: array[0..3] of string = ('duplicates', 'dupliziert', 'ist Duplikat von', 'ist ein Duplikat von');
  RelatesPhrases: array[0..2] of string = ('relates to', 'bezieht sich auf', 'ist verwandt mit');
  // Wörter vor "#12" im Fließtext bzw. nur am Zeilenanfang (sonst passte „Wird benötigt von: #227“).
  InlinePhrases: array[0..5] of string = ('depends on', 'blocked by', 'hängt ab von', 'abhängig von',
    'is blocked by', 'wird blockiert von');
  LeadingPhrases: array[0..4] of string = ('benötigt', 'requires', 'needs', 'depends on', 'blocked by');

function IsOneOf(const AText: string; const ANames: array of string): Boolean;
var
  mName, mText: string;
begin
  Result := False;
  mText := Trim(AText);
  if mText = '' then
    Exit;
  for mName in ANames do
    if SameText(mText, mName) then
      Exit(True);
end;

class function TAtlasTrackerLinks.YouTrackKind(const AName, ASourceToTarget, ATargetToSource, ADirection: string;
  AAggregation: Boolean): TAtlasTrackerLinkKind;
var
  mFamily: TFamily;
  mReversed: Boolean;
  mDirection: string;
begin
  mFamily := TFamily.None;
  mReversed := False;
  if IsOneOf(AName, DependNames) then
    mFamily := TFamily.Depend
  else if IsOneOf(AName, SubtaskNames) then
    mFamily := TFamily.Subtask
  else if IsOneOf(AName, DuplicateNames) then
    mFamily := TFamily.Duplicate
  else if IsOneOf(AName, RelatesNames) then
    mFamily := TFamily.Relates
  else if AAggregation then
    mFamily := TFamily.Subtask
  else if IsOneOf(ASourceToTarget, DependSource) or IsOneOf(ATargetToSource, DependTarget) or
    IsOneOf(ASourceToTarget, DependTarget) or IsOneOf(ATargetToSource, DependSource) then
    mFamily := TFamily.Depend
  else if IsOneOf(ASourceToTarget, SubtaskSource) or IsOneOf(ATargetToSource, SubtaskTarget) or
    IsOneOf(ASourceToTarget, SubtaskTarget) or IsOneOf(ATargetToSource, SubtaskSource) then
    mFamily := TFamily.Subtask
  else if IsOneOf(ASourceToTarget, DuplicateSource) or IsOneOf(ATargetToSource, DuplicateTarget) or
    IsOneOf(ASourceToTarget, DuplicateTarget) or IsOneOf(ATargetToSource, DuplicateSource) then
    mFamily := TFamily.Duplicate
  else if IsOneOf(ASourceToTarget, RelatesPhrases) or IsOneOf(ATargetToSource, RelatesPhrases) then
    mFamily := TFamily.Relates;
  // Eigener Typ mit vertauschten Beschriftungen ("depends on" auf der Seite der Quelle): Richtung umdrehen.
  case mFamily of
    TFamily.Depend:
      mReversed := IsOneOf(ASourceToTarget, DependTarget) and not IsOneOf(ASourceToTarget, DependSource);
    TFamily.Subtask:
      mReversed := IsOneOf(ASourceToTarget, SubtaskTarget) and not IsOneOf(ASourceToTarget, SubtaskSource);
    TFamily.Duplicate:
      mReversed := IsOneOf(ASourceToTarget, DuplicateTarget) and not IsOneOf(ASourceToTarget, DuplicateSource);
  end;
  mDirection := UpperCase(Trim(ADirection));
  if mReversed then
  begin
    if mDirection = 'OUTWARD' then
      mDirection := 'INWARD'
    else if mDirection = 'INWARD' then
      mDirection := 'OUTWARD';
  end;
  Result := TAtlasTrackerLinkKind.Other;
  case mFamily of
    TFamily.Depend:
      if mDirection = 'INWARD' then
        Result := TAtlasTrackerLinkKind.DependsOn
      else if mDirection = 'OUTWARD' then
        Result := TAtlasTrackerLinkKind.Blocks
      else
        Result := TAtlasTrackerLinkKind.Relates;
    TFamily.Subtask:
      if mDirection = 'OUTWARD' then
        Result := TAtlasTrackerLinkKind.Subtask
      else if mDirection = 'INWARD' then
        Result := TAtlasTrackerLinkKind.Parent
      else
        Result := TAtlasTrackerLinkKind.Relates;
    TFamily.Duplicate:
      if mDirection = 'INWARD' then
        Result := TAtlasTrackerLinkKind.Duplicates
      else if mDirection = 'OUTWARD' then
        Result := TAtlasTrackerLinkKind.DuplicatedBy
      else
        Result := TAtlasTrackerLinkKind.Relates;
    TFamily.Relates:
      Result := TAtlasTrackerLinkKind.Relates;
  end;
end;

class function TAtlasTrackerLinks.Collapsed(AKind: TAtlasTrackerLinkKind): Boolean;
begin
  Result := not (AKind in [TAtlasTrackerLinkKind.DependsOn, TAtlasTrackerLinkKind.Blocks,
    TAtlasTrackerLinkKind.Subtask, TAtlasTrackerLinkKind.Parent]);
end;

class function TAtlasTrackerLinks.Groups(const ALinks: TArray<TAtlasTrackerLink>): TArray<TAtlasTrackerLinkGroup>;
var
  mKind: TAtlasTrackerLinkKind;
  mLink: TAtlasTrackerLink;
  mGroup: TAtlasTrackerLinkGroup;
begin
  Result := nil;
  for mKind in GroupOrder do
  begin
    mGroup := Default(TAtlasTrackerLinkGroup);
    mGroup.Kind := mKind;
    mGroup.Links := nil;
    mGroup.Collapsed := Collapsed(mKind);
    for mLink in ALinks do
      if mLink.Kind = mKind then
      begin
        mGroup.Links := mGroup.Links + [mLink];
        Inc(mGroup.Total);
        if mLink.StateKnown and mLink.Resolved then
          Inc(mGroup.Done);
      end;
    if mGroup.Total > 0 then
      Result := Result + [mGroup];
  end;
end;

class function TAtlasTrackerLinks.Progress(const ALinks: TArray<TAtlasTrackerLink>; out ADone,
  ATotal: Integer): Boolean;
var
  mLink: TAtlasTrackerLink;
begin
  ADone := 0;
  ATotal := 0;
  for mLink in ALinks do
    if mLink.Kind = TAtlasTrackerLinkKind.Subtask then
    begin
      Inc(ATotal);
      if mLink.StateKnown and mLink.Resolved then
        Inc(ADone);
    end;
  Result := ATotal > 0;
end;

class function TAtlasTrackerLinks.ProgressText(ADone, ATotal: Integer): string;
begin
  Result := IntToStr(ADone) + '/' + IntToStr(ATotal);
end;

class function TAtlasTrackerLinks.OpenBlockers(const ALinks: TArray<TAtlasTrackerLink>): TArray<TAtlasTrackerLink>;
var
  mLink: TAtlasTrackerLink;
begin
  Result := nil;
  for mLink in ALinks do
    if mLink.Blocking then
      Result := Result + [mLink];
end;

class function TAtlasTrackerLinks.WarnOnStart(AWarn: Boolean;
  const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerLink>;
begin
  Result := nil;
  if AWarn then
    Result := OpenBlockers(ADetails.Links);
end;

class function TAtlasTrackerLinks.Locked(const ADetails: TAtlasTrackerDetails): Boolean;
begin
  Result := Length(OpenBlockers(ADetails.Links)) > 0;
end;

class function TAtlasTrackerLinks.Mark(const ALink: TAtlasTrackerLink): TAtlasTrackerLinkMark;
begin
  if not ALink.StateKnown then
    Result := TAtlasTrackerLinkMark.Unknown
  else if ALink.Resolved then
    Result := TAtlasTrackerLinkMark.Done
  else if ALink.Blocking then
    Result := TAtlasTrackerLinkMark.Blocking
  else
    Result := TAtlasTrackerLinkMark.Open;
end;

/// <summary>Ab AStart (1-basiert) in ALine: "#12, #13 und #14" lesen; Trenner davor (":", "*", "_", Leerraum)
/// werden übersprungen.</summary>
procedure ReadNumbers(const ALine: string; AStart: Integer; var ANumbers: TArray<Integer>);
var
  mPos, mFrom, mNumber, mIndex: Integer;
  mKnown: Boolean;
begin
  mPos := AStart;
  while (mPos <= Length(ALine)) and CharInSet(ALine[mPos], [':', '*', '_', ' ', #9]) do
    Inc(mPos);
  while (mPos <= Length(ALine)) and (ALine[mPos] = '#') do
  begin
    Inc(mPos);
    mFrom := mPos;
    while (mPos <= Length(ALine)) and CharInSet(ALine[mPos], ['0'..'9']) do
      Inc(mPos);
    if (mPos = mFrom) or not TryStrToInt(Copy(ALine, mFrom, mPos - mFrom), mNumber) or (mNumber <= 0) then
      Exit;
    // Kein "#12a" und kein "#12-…" (Anker, Kennungen anderer Art).
    if (mPos <= Length(ALine)) and CharInSet(ALine[mPos], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Exit;
    mKnown := False;
    for mIndex := 0 to High(ANumbers) do
      if ANumbers[mIndex] = mNumber then
        mKnown := True;
    if not mKnown then
    begin
      if Length(ANumbers) >= TAtlasTrackerLinks.MaxTextDependencies then
        Exit;
      ANumbers := ANumbers + [mNumber];
    end;
    // Trenner bis zur nächsten Nummer: ",", ";", "*", Leerraum, "und", "and".
    while mPos <= Length(ALine) do
    begin
      if CharInSet(ALine[mPos], [',', ';', '*', ' ', #9]) then
        Inc(mPos)
      else if SameText(Copy(ALine, mPos, 4), 'und ') or SameText(Copy(ALine, mPos, 4), 'and ') then
        Inc(mPos, 4)
      else
        Break;
    end;
  end;
end;

class function TAtlasTrackerLinks.TextDependencies(const AText: string): TArray<Integer>;
var
  mLines: TArray<string>;
  mLine, mLower, mPhrase, mLead: string;
  mAt, mStart: Integer;
begin
  Result := nil;
  mLines := AText.Replace(#13, '').Split([#10]);
  for mLine in mLines do
  begin
    mLower := AnsiLowerCase(mLine);
    // Im Fließtext: "depends on #12".
    for mPhrase in InlinePhrases do
    begin
      mAt := Pos(mPhrase, mLower);
      while mAt > 0 do
      begin
        // Nur als eigenes Wort ("independs on" zählt nicht).
        if (mAt = 1) or not CharInSet(mLower[mAt - 1], ['a'..'z', '0'..'9', '_']) then
          ReadNumbers(mLine, mAt + Length(mPhrase), Result);
        mAt := PosEx(mPhrase, mLower, mAt + Length(mPhrase));
      end;
    end;
    // Am Zeilenanfang (nach Aufzählungszeichen und Fettdruck): "- **Benötigt:** #765, #1264".
    mStart := 1;
    while (mStart <= Length(mLower)) and CharInSet(mLower[mStart], [' ', #9, '-', '*', '_', '>']) do
      Inc(mStart);
    for mLead in LeadingPhrases do
      if Copy(mLower, mStart, Length(mLead)) = mLead then
        ReadNumbers(mLine, mStart + Length(mLead), Result);
  end;
end;

end.
