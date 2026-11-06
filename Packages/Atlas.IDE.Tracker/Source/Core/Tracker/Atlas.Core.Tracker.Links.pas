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
  begin
    Exit;
  end;
  for mName in ANames do
  begin
    if SameText(mText, mName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Familie aus dem Namen des Linktyps; ohne bekannten Namen bei AAggregation Subtask.</summary>
function FamilyByName(const AName: string; AAggregation: Boolean): TFamily;
begin
  Result := TFamily.None;
  if IsOneOf(AName, DependNames) then
  begin
    Result := TFamily.Depend;
  end
  else if IsOneOf(AName, SubtaskNames) then
  begin
    Result := TFamily.Subtask;
  end
  else if IsOneOf(AName, DuplicateNames) then
  begin
    Result := TFamily.Duplicate;
  end
  else if IsOneOf(AName, RelatesNames) then
  begin
    Result := TFamily.Relates;
  end
  else if AAggregation then
  begin
    Result := TFamily.Subtask;
  end;
end;

/// <summary>Eine der Beschriftungen gehört zu ASource bzw. ATarget, auf welcher Seite auch immer.</summary>
function EitherSide(const ASourceToTarget, ATargetToSource: string; const ASource, ATarget: array of string):
  Boolean;
begin
  Result := IsOneOf(ASourceToTarget, ASource) or IsOneOf(ATargetToSource, ATarget) or
    IsOneOf(ASourceToTarget, ATarget) or IsOneOf(ATargetToSource, ASource);
end;

/// <summary>Familie aus den Beschriftungen (eigene Linktypen).</summary>
function FamilyByPhrases(const ASourceToTarget, ATargetToSource: string): TFamily;
begin
  Result := TFamily.None;
  if EitherSide(ASourceToTarget, ATargetToSource, DependSource, DependTarget) then
  begin
    Result := TFamily.Depend;
  end
  else if EitherSide(ASourceToTarget, ATargetToSource, SubtaskSource, SubtaskTarget) then
  begin
    Result := TFamily.Subtask;
  end
  else if EitherSide(ASourceToTarget, ATargetToSource, DuplicateSource, DuplicateTarget) then
  begin
    Result := TFamily.Duplicate;
  end
  else if IsOneOf(ASourceToTarget, RelatesPhrases) or IsOneOf(ATargetToSource, RelatesPhrases) then
  begin
    Result := TFamily.Relates;
  end;
end;

/// <summary>Eigener Typ mit vertauschten Beschriftungen ("depends on" auf der Seite der Quelle).</summary>
function Reversed(AFamily: TFamily; const ASourceToTarget: string): Boolean;
begin
  Result := False;
  case AFamily of
    TFamily.Depend:
      Result := IsOneOf(ASourceToTarget, DependTarget) and not IsOneOf(ASourceToTarget, DependSource);
    TFamily.Subtask:
      Result := IsOneOf(ASourceToTarget, SubtaskTarget) and not IsOneOf(ASourceToTarget, SubtaskSource);
    TFamily.Duplicate:
      Result := IsOneOf(ASourceToTarget, DuplicateTarget) and not IsOneOf(ASourceToTarget, DuplicateSource);
    TFamily.None, TFamily.Relates: ;
  end;
end;

/// <summary>OUTWARD und INWARD vertauscht, alles andere unverändert.</summary>
function Flipped(const ADirection: string): string;
begin
  Result := ADirection;
  if ADirection = 'OUTWARD' then
  begin
    Result := 'INWARD';
  end
  else if ADirection = 'INWARD' then
  begin
    Result := 'OUTWARD';
  end;
end;

/// <summary>AInward bzw. AOutward nach der Richtung; ohne Richtung Relates.</summary>
function Directed(const ADirection: string; AInward, AOutward: TAtlasTrackerLinkKind): TAtlasTrackerLinkKind;
begin
  Result := TAtlasTrackerLinkKind.Relates;
  if ADirection = 'INWARD' then
  begin
    Result := AInward;
  end
  else if ADirection = 'OUTWARD' then
  begin
    Result := AOutward;
  end;
end;

class function TAtlasTrackerLinks.YouTrackKind(const AName, ASourceToTarget, ATargetToSource, ADirection: string;
  AAggregation: Boolean): TAtlasTrackerLinkKind;
var
  mFamily: TFamily;
  mDirection: string;
begin
  mFamily := FamilyByName(AName, AAggregation);
  if mFamily = TFamily.None then
  begin
    mFamily := FamilyByPhrases(ASourceToTarget, ATargetToSource);
  end;
  mDirection := UpperCase(Trim(ADirection));
  // Vertauschte Beschriftungen: Richtung umdrehen.
  if Reversed(mFamily, ASourceToTarget) then
  begin
    mDirection := Flipped(mDirection);
  end;
  case mFamily of
    TFamily.Depend:
      Result := Directed(mDirection, TAtlasTrackerLinkKind.DependsOn, TAtlasTrackerLinkKind.Blocks);
    TFamily.Subtask:
      Result := Directed(mDirection, TAtlasTrackerLinkKind.Parent, TAtlasTrackerLinkKind.Subtask);
    TFamily.Duplicate:
      Result := Directed(mDirection, TAtlasTrackerLinkKind.Duplicates, TAtlasTrackerLinkKind.DuplicatedBy);
    TFamily.Relates:
      Result := TAtlasTrackerLinkKind.Relates;
  else
    Result := TAtlasTrackerLinkKind.Other;
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
    begin
      if mLink.Kind = mKind then
      begin
        mGroup.Links := mGroup.Links + [mLink];
        Inc(mGroup.Total);
        if mLink.StateKnown and mLink.Resolved then
        begin
          Inc(mGroup.Done);
        end;
      end;
    end;
    if mGroup.Total > 0 then
    begin
      Result := Result + [mGroup];
    end;
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
  begin
    if mLink.Kind = TAtlasTrackerLinkKind.Subtask then
    begin
      Inc(ATotal);
      if mLink.StateKnown and mLink.Resolved then
      begin
        Inc(ADone);
      end;
    end;
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
  begin
    if mLink.Blocking then
    begin
      Result := Result + [mLink];
    end;
  end;
end;

class function TAtlasTrackerLinks.WarnOnStart(AWarn: Boolean;
  const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerLink>;
begin
  Result := nil;
  if AWarn then
  begin
    Result := OpenBlockers(ADetails.Links);
  end;
end;

class function TAtlasTrackerLinks.Locked(const ADetails: TAtlasTrackerDetails): Boolean;
begin
  Result := Length(OpenBlockers(ADetails.Links)) > 0;
end;

class function TAtlasTrackerLinks.Mark(const ALink: TAtlasTrackerLink): TAtlasTrackerLinkMark;
begin
  if not ALink.StateKnown then
  begin
    Result := TAtlasTrackerLinkMark.Unknown;
  end
  else if ALink.Resolved then
  begin
    Result := TAtlasTrackerLinkMark.Done;
  end
  else if ALink.Blocking then
  begin
    Result := TAtlasTrackerLinkMark.Blocking;
  end
  else
  begin
    Result := TAtlasTrackerLinkMark.Open;
  end;
end;

/// <summary>Ab APos: Trenner bis zur nächsten Nummer (",", ";", "*", Leerraum, "und", "and").</summary>
function SkipNumberSeparators(const ALine: string; APos: Integer): Integer;
begin
  Result := APos;
  while Result <= Length(ALine) do
  begin
    if CharInSet(ALine[Result], [',', ';', '*', ' ', #9]) then
    begin
      Inc(Result);
    end
    else if SameText(Copy(ALine, Result, 4), 'und ') or SameText(Copy(ALine, Result, 4), 'and ') then
    begin
      Inc(Result, 4);
    end
    else
    begin
      Break;
    end;
  end;
end;

/// <summary>Nummer nach dem "#" ab APos; APos dahinter. False ohne Nummer und bei "#12a" bzw. "#12-…" (Anker,
/// Kennungen anderer Art).</summary>
function ReadNumber(const ALine: string; var APos: Integer; out ANumber: Integer): Boolean;
var
  mFrom: Integer;
begin
  mFrom := APos;
  while (APos <= Length(ALine)) and CharInSet(ALine[APos], ['0'..'9']) do
  begin
    Inc(APos);
  end;
  Result := (APos > mFrom) and TryStrToInt(Copy(ALine, mFrom, APos - mFrom), ANumber) and (ANumber > 0) and
    not ((APos <= Length(ALine)) and CharInSet(ALine[APos], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']));
end;

/// <summary>ANumber anfügen, wenn neu; False, wenn die Liste schon voll ist.</summary>
function AddNumber(var ANumbers: TArray<Integer>; ANumber: Integer): Boolean;
var
  mKnown: Integer;
begin
  for mKnown in ANumbers do
  begin
    if mKnown = ANumber then
    begin
      Exit(True);
    end;
  end;
  Result := Length(ANumbers) < TAtlasTrackerLinks.MaxTextDependencies;
  if Result then
  begin
    ANumbers := ANumbers + [ANumber];
  end;
end;

/// <summary>Ab AStart (1-basiert) in ALine: "#12, #13 und #14" lesen; Trenner davor (":", "*", "_", Leerraum)
/// werden übersprungen.</summary>
procedure ReadNumbers(const ALine: string; AStart: Integer; var ANumbers: TArray<Integer>);
var
  mPos, mNumber: Integer;
begin
  mPos := AStart;
  while (mPos <= Length(ALine)) and CharInSet(ALine[mPos], [':', '*', '_', ' ', #9]) do
  begin
    Inc(mPos);
  end;
  while (mPos <= Length(ALine)) and (ALine[mPos] = '#') do
  begin
    Inc(mPos);
    if not ReadNumber(ALine, mPos, mNumber) or not AddNumber(ANumbers, mNumber) then
    begin
      Exit;
    end;
    mPos := SkipNumberSeparators(ALine, mPos);
  end;
end;

/// <summary>Im Fließtext: "depends on #12", nur als eigenes Wort ("independs on" zählt nicht).</summary>
procedure ReadInline(const ALine, ALower: string; var ANumbers: TArray<Integer>);
var
  mPhrase: string;
  mAt: Integer;
begin
  for mPhrase in InlinePhrases do
  begin
    mAt := Pos(mPhrase, ALower);
    while mAt > 0 do
    begin
      if (mAt = 1) or not CharInSet(ALower[mAt - 1], ['a'..'z', '0'..'9', '_']) then
      begin
        ReadNumbers(ALine, mAt + Length(mPhrase), ANumbers);
      end;
      mAt := PosEx(mPhrase, ALower, mAt + Length(mPhrase));
    end;
  end;
end;

class function TAtlasTrackerLinks.TextDependencies(const AText: string): TArray<Integer>;
var
  mLine, mLower, mLead: string;
  mStart: Integer;
begin
  Result := nil;
  for mLine in AText.Replace(#13, '').Split([#10]) do
  begin
    mLower := AnsiLowerCase(mLine);
    ReadInline(mLine, mLower, Result);
    // Am Zeilenanfang (nach Aufzählungszeichen und Fettdruck): "- **Benötigt:** #765, #1264".
    mStart := 1;
    while (mStart <= Length(mLower)) and CharInSet(mLower[mStart], [' ', #9, '-', '*', '_', '>']) do
    begin
      Inc(mStart);
    end;
    for mLead in LeadingPhrases do
    begin
      if Copy(mLower, mStart, Length(mLead)) = mLead then
      begin
        ReadNumbers(mLine, mStart + Length(mLead), Result);
      end;
    end;
  end;
end;

end.
