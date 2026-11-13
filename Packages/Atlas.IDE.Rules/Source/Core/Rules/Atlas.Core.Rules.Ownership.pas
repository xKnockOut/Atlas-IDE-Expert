unit Atlas.Core.Rules.Ownership;

// Marke „Wer gibt das frei?“ (#1877) ohne VCL und Open Tools API: Antwort des
// Befehls atlas.server.ownership lesen, Ton und Beschriftung je Stelle, Filter
// „nur Problemfälle“ (editor.ownershipHints.onlyProblems), Marke einer Zeile
// samt Sprungziel und Tooltip, und wann neu zu fragen ist.
// - Die Einstufung rechnet der Server (Atlas.Common.Leaks.Ownership) mit den
//   Befunden der Leck-Regeln desselben Textes: Rot steht nur, wo eine Regel
//   meldet.
// - Ton: grün (Safe) bei Destroy, finally, Owner, besitzender Liste und
//   Referenzzählung; gelb (Elsewhere) bei Freigabe in einer anderen Methode,
//   Rückgabe, Weitergabe und unklar; rot (Never) bei „nie freigegeben“.
// - Eine Marke zählt nur, solange ihre Zeile noch so lautet wie beim Abruf
//   (lineText), damit sie nach dem Tippen nicht an fremden Zeilen steht.
// - Neu fragen: bei einer anderen Datei und nach jeder neuen Prüfung dieser
//   Datei (kein eigener Zeitgeber).

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Freigabe wie TOwnershipSites.cKindNames des Servers.</summary>
  TAtlasOwnershipKind = (InDestroy, InFinally, Freed, Owner, OwnedList, RefCounted, Returned, Passed, Unknown, Never);
  /// <summary>Farbe der Marke: grün, gelb, rot.</summary>
  TAtlasOwnershipTone = (Safe, Elsewhere, Never);
  /// <summary>Behälter-Hinweis wie TOwnershipSites.cContainerNames.</summary>
  TAtlasOwnershipContainer = (None, OwnsElements, ElementsOwned);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Erzeugung T.Create(…) aus der Antwort; Zeilen ab 0.</summary>
  TAtlasOwnershipMark = record
    Line: Integer;
    Character: Integer;
    /// <summary>Zeile der Erzeugung beim Abruf, ohne Leerraum am Ende.</summary>
    LineText: string;
    ClassName: string;
    Target: string;
    Kind: TAtlasOwnershipKind;
    /// <summary>Zeile der Freigabe; -1 ohne.</summary>
    FreeLine: Integer;
    Detail: string;
    Container: TAtlasOwnershipContainer;
    ContainerOwner: string;
    Rule: string;
    Message: string;
    function Tone: TAtlasOwnershipTone;
  end;

  /// <summary>Texte der Marken und Tooltips in der Sprache der IDE (aus Atlas.UI.Rules.Strings).</summary>
  TAtlasOwnershipTexts = record
    /// <summary>Beschriftung je Art; InDestroy, InFinally und Freed mit %d (Zeile), Owner, OwnedList und Passed
    /// mit %s.</summary>
    Labels: array[TAtlasOwnershipKind] of string;
    /// <summary>Freed mit Methode: %s, %d.</summary>
    FreedIn: string;
    /// <summary>Passed ohne Empfänger.</summary>
    PassedSomewhere: string;
    /// <summary>Erklärung je Art im Tooltip; Never mit %s (Regel).</summary>
    Reasons: array[TAtlasOwnershipKind] of string;
    /// <summary>Anhang der Beschriftung je Behälter; ElementsOwned mit %s.</summary>
    ContainerLabels: array[TAtlasOwnershipContainer] of string;
    /// <summary>Erklärung je Behälter im Tooltip; ElementsOwned mit %s.</summary>
    ContainerReasons: array[TAtlasOwnershipContainer] of string;
    /// <summary>Überschrift des Tooltips mit %s (Ziel bzw. Klasse).</summary>
    Title: string;
    /// <summary>Hinweis auf den Klick mit %d (Zeile).</summary>
    Jump: string;
  end;

  /// <summary>Zuletzt gefragter Stand: Datei und Zeit der Prüfung, nach der gefragt wurde.</summary>
  TAtlasOwnershipFetch = record
    FileName: string;
    CheckAt: TDateTime;
    /// <summary>Neu fragen? Andere Datei als AFileName, oder ACheckFile ist AFileName und seit dem letzten Abruf
    /// neu geprüft (ACheckAt).</summary>
    function Due(const AFileName, ACheckFile: string; ACheckAt: TDateTime): Boolean;
    /// <summary>Abruf für AFileName nach der Prüfung ACheckAt gestellt.</summary>
    procedure Asked(const AFileName, ACheckFile: string; ACheckAt: TDateTime);
    procedure Reset;
  end;

  TAtlasOwnershipMarks = class
  public const
    cCommand = 'atlas.server.ownership';
    cKindNames: array[TAtlasOwnershipKind] of string = ('destroy', 'finally', 'freed', 'owner', 'ownedList',
      'interface', 'returned', 'passed', 'unknown', 'never');
    cContainerNames: array[TAtlasOwnershipContainer] of string = ('', 'ownsElements', 'elementsOwned');
  public
    /// <summary>Argumente des Befehls: ["AUri"].</summary>
    class function Arguments(const AUri: string): string; static;
    /// <summary>Stellen der Antwort AJson; nil bei leerer oder unlesbarer Antwort. Unbekannte Arten fallen weg.
    /// </summary>
    class function Parse(const AJson: string): TArray<TAtlasOwnershipMark>; static;
    /// <summary>Stellen nach editor.ownershipHints.onlyProblems: ohne grüne, wenn AOnlyProblems.</summary>
    class function Visible(const AMarks: TArray<TAtlasOwnershipMark>;
      AOnlyProblems: Boolean): TArray<TAtlasOwnershipMark>; static;
    /// <summary>Stellen der Zeile ALine (ab 0), deren Zeilentext noch ALineText ist (ohne Leerraum am Ende).
    /// </summary>
    class function AtLine(const AMarks: TArray<TAtlasOwnershipMark>; ALine: Integer;
      const ALineText: string): TArray<TAtlasOwnershipMark>; static;
    /// <summary>Beschriftung einer Stelle.</summary>
    class function Caption(const AMark: TAtlasOwnershipMark; const ATexts: TAtlasOwnershipTexts): string; static;
    /// <summary>Beschriftung mehrerer Stellen einer Zeile, mit „ | “ getrennt.</summary>
    class function LineCaption(const AMarks: TArray<TAtlasOwnershipMark>;
      const ATexts: TAtlasOwnershipTexts): string; static;
    /// <summary>Kräftigster Ton der Stellen: rot vor gelb vor grün.</summary>
    class function LineTone(const AMarks: TArray<TAtlasOwnershipMark>): TAtlasOwnershipTone; static;
    /// <summary>Zeile der ersten Freigabe (ab 0); -1 ohne.</summary>
    class function JumpLine(const AMarks: TArray<TAtlasOwnershipMark>): Integer; static;
    /// <summary>Überschrift des Tooltips (Ziel der ersten Stelle, sonst ihre Klasse).</summary>
    class function TipTitle(const AMarks: TArray<TAtlasOwnershipMark>; const ATexts: TAtlasOwnershipTexts): string;
      static;
    /// <summary>Text des Tooltips: je Stelle Beschriftung, Weg dorthin, Behälter, Meldung der Regel; am Ende der
    /// Klick.</summary>
    class function TipText(const AMarks: TArray<TAtlasOwnershipMark>; const ATexts: TAtlasOwnershipTexts): string;
      static;
  end;

implementation

{ TAtlasOwnershipMark }

function TAtlasOwnershipMark.Tone: TAtlasOwnershipTone;
begin
  case Kind of
    TAtlasOwnershipKind.InDestroy, TAtlasOwnershipKind.InFinally, TAtlasOwnershipKind.Owner,
    TAtlasOwnershipKind.OwnedList, TAtlasOwnershipKind.RefCounted:
      Result := TAtlasOwnershipTone.Safe;
    TAtlasOwnershipKind.Never:
      Result := TAtlasOwnershipTone.Never;
  else
    Result := TAtlasOwnershipTone.Elsewhere;
  end;
end;

{ TAtlasOwnershipFetch }

function TAtlasOwnershipFetch.Due(const AFileName, ACheckFile: string; ACheckAt: TDateTime): Boolean;
begin
  Result := (AFileName <> '') and (not SameText(FileName, AFileName) or
    (SameText(ACheckFile, AFileName) and (ACheckAt > CheckAt)));
end;

procedure TAtlasOwnershipFetch.Asked(const AFileName, ACheckFile: string; ACheckAt: TDateTime);
begin
  FileName := AFileName;
  CheckAt := 0;
  if SameText(ACheckFile, AFileName) then
  begin
    CheckAt := ACheckAt;
  end;
end;

procedure TAtlasOwnershipFetch.Reset;
begin
  FileName := '';
  CheckAt := 0;
end;

{ TAtlasOwnershipMarks }

class function TAtlasOwnershipMarks.Arguments(const AUri: string): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

function KindOf(const AName: string; out AKind: TAtlasOwnershipKind): Boolean;
var
  mKind: TAtlasOwnershipKind;
begin
  for mKind := Low(TAtlasOwnershipKind) to High(TAtlasOwnershipKind) do
  begin
    if AName = TAtlasOwnershipMarks.cKindNames[mKind] then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasOwnershipKind.Unknown;
  Result := False;
end;

function ContainerOf(const AName: string): TAtlasOwnershipContainer;
var
  mContainer: TAtlasOwnershipContainer;
begin
  Result := TAtlasOwnershipContainer.None;
  for mContainer := Succ(Low(TAtlasOwnershipContainer)) to High(TAtlasOwnershipContainer) do
  begin
    if AName = TAtlasOwnershipMarks.cContainerNames[mContainer] then
    begin
      Result := mContainer;
    end;
  end;
end;

/// <summary>Stelle aus einem Element von sites; False ohne Art oder Zeile.</summary>
function MarkOf(AItem: TJSONObject; out AMark: TAtlasOwnershipMark): Boolean;
begin
  AMark := Default(TAtlasOwnershipMark);
  Result := KindOf(AItem.GetValue<string>('kind', ''), AMark.Kind);
  if not Result then
  begin
    Exit;
  end;
  AMark.Line := AItem.GetValue<Integer>('line', -1);
  AMark.Character := AItem.GetValue<Integer>('character', 0);
  AMark.LineText := AItem.GetValue<string>('lineText', '');
  AMark.ClassName := AItem.GetValue<string>('className', '');
  AMark.Target := AItem.GetValue<string>('target', '');
  AMark.FreeLine := AItem.GetValue<Integer>('freeLine', -1);
  AMark.Detail := AItem.GetValue<string>('detail', '');
  AMark.Container := ContainerOf(AItem.GetValue<string>('container', ''));
  AMark.ContainerOwner := AItem.GetValue<string>('containerOwner', '');
  AMark.Rule := AItem.GetValue<string>('rule', '');
  AMark.Message := AItem.GetValue<string>('message', '');
  Result := AMark.Line >= 0;
end;

class function TAtlasOwnershipMarks.Parse(const AJson: string): TArray<TAtlasOwnershipMark>;
var
  mValue, mItem: TJSONValue;
  mSites: TJSONArray;
  mMark: TAtlasOwnershipMark;
begin
  Result := nil;
  if AJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) or not TJSONObject(mValue).TryGetValue<TJSONArray>('sites', mSites) then
    begin
      Exit;
    end;
    for mItem in mSites do
    begin
      if (mItem is TJSONObject) and MarkOf(TJSONObject(mItem), mMark) then
      begin
        Result := Result + [mMark];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasOwnershipMarks.Visible(const AMarks: TArray<TAtlasOwnershipMark>;
  AOnlyProblems: Boolean): TArray<TAtlasOwnershipMark>;
var
  mMark: TAtlasOwnershipMark;
begin
  if not AOnlyProblems then
  begin
    Exit(AMarks);
  end;
  Result := nil;
  for mMark in AMarks do
  begin
    if mMark.Tone <> TAtlasOwnershipTone.Safe then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

class function TAtlasOwnershipMarks.AtLine(const AMarks: TArray<TAtlasOwnershipMark>; ALine: Integer;
  const ALineText: string): TArray<TAtlasOwnershipMark>;
var
  mMark: TAtlasOwnershipMark;
  mText: string;
begin
  Result := nil;
  mText := TrimRight(ALineText);
  for mMark in AMarks do
  begin
    if (mMark.Line = ALine) and (mMark.LineText = mText) then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

class function TAtlasOwnershipMarks.Caption(const AMark: TAtlasOwnershipMark;
  const ATexts: TAtlasOwnershipTexts): string;
var
  mLabel: string;
begin
  mLabel := ATexts.Labels[AMark.Kind];
  case AMark.Kind of
    TAtlasOwnershipKind.InDestroy, TAtlasOwnershipKind.InFinally:
      Result := Format(mLabel, [AMark.FreeLine + 1]);
    TAtlasOwnershipKind.Freed:
      if AMark.Detail <> '' then
      begin
        Result := Format(ATexts.FreedIn, [AMark.Detail, AMark.FreeLine + 1]);
      end
      else
      begin
        Result := Format(mLabel, [AMark.FreeLine + 1]);
      end;
    TAtlasOwnershipKind.Owner, TAtlasOwnershipKind.OwnedList:
      Result := Format(mLabel, [AMark.Detail]);
    TAtlasOwnershipKind.Passed:
      if AMark.Detail <> '' then
      begin
        Result := Format(mLabel, [AMark.Detail]);
      end
      else
      begin
        Result := ATexts.PassedSomewhere;
      end;
  else
    Result := mLabel;
  end;
  if AMark.Container = TAtlasOwnershipContainer.OwnsElements then
  begin
    Result := Result + ATexts.ContainerLabels[AMark.Container];
  end
  else if AMark.Container = TAtlasOwnershipContainer.ElementsOwned then
  begin
    Result := Result + Format(ATexts.ContainerLabels[AMark.Container], [AMark.ContainerOwner]);
  end;
end;

class function TAtlasOwnershipMarks.LineCaption(const AMarks: TArray<TAtlasOwnershipMark>;
  const ATexts: TAtlasOwnershipTexts): string;
var
  mMark: TAtlasOwnershipMark;
begin
  Result := '';
  for mMark in AMarks do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + Caption(mMark, ATexts);
  end;
end;

class function TAtlasOwnershipMarks.LineTone(const AMarks: TArray<TAtlasOwnershipMark>): TAtlasOwnershipTone;
var
  mMark: TAtlasOwnershipMark;
begin
  Result := TAtlasOwnershipTone.Safe;
  for mMark in AMarks do
  begin
    if Ord(mMark.Tone) > Ord(Result) then
    begin
      Result := mMark.Tone;
    end;
  end;
end;

class function TAtlasOwnershipMarks.JumpLine(const AMarks: TArray<TAtlasOwnershipMark>): Integer;
var
  mMark: TAtlasOwnershipMark;
begin
  for mMark in AMarks do
  begin
    if mMark.FreeLine >= 0 then
    begin
      Exit(mMark.FreeLine);
    end;
  end;
  Result := -1;
end;

class function TAtlasOwnershipMarks.TipTitle(const AMarks: TArray<TAtlasOwnershipMark>;
  const ATexts: TAtlasOwnershipTexts): string;
var
  mName: string;
begin
  Result := '';
  if AMarks = nil then
  begin
    Exit;
  end;
  mName := AMarks[0].Target;
  if mName = '' then
  begin
    mName := AMarks[0].ClassName;
  end;
  Result := Format(ATexts.Title, [mName]);
end;

/// <summary>Weg zur Einstufung einer Stelle: Erklärung der Art, Meldung der Regel bzw. Grund, Behälter.</summary>
function Reason(const AMark: TAtlasOwnershipMark; const ATexts: TAtlasOwnershipTexts): string;
begin
  if AMark.Kind = TAtlasOwnershipKind.Never then
  begin
    Result := Format(ATexts.Reasons[AMark.Kind], [AMark.Rule]);
  end
  else
  begin
    Result := ATexts.Reasons[AMark.Kind];
  end;
  if AMark.Message <> '' then
  begin
    Result := Result + sLineBreak + AMark.Message;
  end;
  if AMark.Container = TAtlasOwnershipContainer.OwnsElements then
  begin
    Result := Result + sLineBreak + ATexts.ContainerReasons[AMark.Container];
  end
  else if AMark.Container = TAtlasOwnershipContainer.ElementsOwned then
  begin
    Result := Result + sLineBreak + Format(ATexts.ContainerReasons[AMark.Container], [AMark.ContainerOwner]);
  end;
end;

class function TAtlasOwnershipMarks.TipText(const AMarks: TArray<TAtlasOwnershipMark>;
  const ATexts: TAtlasOwnershipTexts): string;
var
  mMark: TAtlasOwnershipMark;
  mJump: Integer;
begin
  Result := '';
  for mMark in AMarks do
  begin
    if Result <> '' then
    begin
      Result := Result + sLineBreak + sLineBreak;
    end;
    Result := Result + mMark.ClassName + ': ' + Caption(mMark, ATexts) + sLineBreak + Reason(mMark, ATexts);
  end;
  mJump := JumpLine(AMarks);
  if mJump >= 0 then
  begin
    Result := Result + sLineBreak + sLineBreak + Format(ATexts.Jump, [mJump + 1]);
  end;
end;

end.
