unit Atlas.Core.Forms.Changes;

// Änderungen des Servers an einem offenen Formular (#402), Teil ohne VCL und
// Open Tools API. Die Datei auf der Platte zu ändern hilft nicht: Der
// Designer überschreibt sie beim nächsten Speichern. Atlas wendet die
// Änderungen deshalb auf den zuletzt gesendeten Formulartext an und
// vergleicht Zeile für Zeile. Unterstützt sind geänderte Ereignis-Zuordnungen
// („OnClick = Alt“ → „OnClick = Neu“, etwa nach dem Umbenennen eines
// Handlers); die IDE-Schicht setzt sie über den Designer. Alles andere
// (neue oder umbenannte Komponenten, andere Eigenschaften) meldet Diff als
// nicht unterstützt, und Atlas ändert dann nichts.

interface

uses
  System.SysUtils;

type
  TAtlasFormEventChange = record
    /// <summary>Name der Komponente; '' = das Formular selbst.</summary>
    Component: string;
    /// <summary>Ereignis-Eigenschaft, z. B. OnClick.</summary>
    EventName: string;
    OldHandler: string;
    NewHandler: string;
  end;

  TAtlasFormChanges = class
  public
    /// <summary>Vergleicht zwei Formulartexte. True, wenn sie sich höchstens in Ereignis-Zuordnungen
    /// unterscheiden (AChanges ist dann die Liste); False mit AReason sonst.</summary>
    class function Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
      out AReason: string): Boolean; static;
    /// <summary>Name aus einer Zeile "object Name: TTyp" (auch inherited, inline); '' sonst.</summary>
    class function ObjectName(const ALine: string; out AIsObject: Boolean): string; static;
  end;

implementation

uses
  Atlas.Text.Lines;

function IsIdentifier(const AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := AValue <> '';
  for Index := 1 to Length(AValue) do
    if not (CharInSet(AValue[Index], ['A'..'Z', 'a'..'z', '_']) or
      ((Index > 1) and CharInSet(AValue[Index], ['0'..'9']))) then
      Exit(False);
end;

/// <summary>"OnClick = Button1Click" → OnClick, Button1Click; False bei anderen Zeilen.</summary>
function EventLine(const ALine: string; out AName, AValue: string): Boolean;
var
  Separator: Integer;
begin
  Separator := Pos(' = ', ALine);
  Result := Separator > 0;
  if not Result then
    Exit;
  AName := Trim(Copy(ALine, 1, Separator - 1));
  AValue := Trim(Copy(ALine, Separator + 3, MaxInt));
  Result := (Length(AName) > 2) and AName.StartsWith('On') and CharInSet(AName[3], ['A'..'Z']) and
    IsIdentifier(AName) and IsIdentifier(AValue);
end;

class function TAtlasFormChanges.ObjectName(const ALine: string; out AIsObject: Boolean): string;
var
  Line, Keyword: string;
  Colon: Integer;
begin
  Result := '';
  Line := Trim(ALine);
  AIsObject := False;
  for Keyword in TArray<string>.Create('object ', 'inherited ', 'inline ') do
    if Line.StartsWith(Keyword, True) then
    begin
      AIsObject := True;
      Line := Trim(Copy(Line, Length(Keyword) + 1, MaxInt));
      Colon := Pos(':', Line);
      // Ohne Doppelpunkt ("object TTimer") hat die Komponente keinen Namen.
      if Colon > 0 then
        Result := Trim(Copy(Line, 1, Colon - 1));
      Exit;
    end;
end;

class function TAtlasFormChanges.Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
  out AReason: string): Boolean;
var
  OldLines, NewLines, Stack: TArray<string>;
  Index: Integer;
  Name, Trimmed, OldName, OldValue, NewName, NewValue: string;
  IsObject: Boolean;
  Change: TAtlasFormEventChange;
begin
  AChanges := nil;
  AReason := '';
  OldLines := TTextLines.SplitLines(AOld);
  NewLines := TTextLines.SplitLines(ANew);
  if Length(OldLines) <> Length(NewLines) then
  begin
    AReason := 'Zeilen hinzugefügt oder entfernt';
    Exit(False);
  end;
  Stack := nil;
  for Index := 0 to High(OldLines) do
  begin
    Name := ObjectName(OldLines[Index], IsObject);
    Trimmed := Trim(OldLines[Index]);
    if IsObject then
      Stack := Stack + [Name]
    else if SameText(Trimmed, 'item') then
      Stack := Stack + ['']
    // Das letzte Element einer Kollektion endet mit "end>".
    else if (SameText(Trimmed, 'end') or SameText(Trimmed, 'end>')) and (Length(Stack) > 0) then
      SetLength(Stack, Length(Stack) - 1);
    if OldLines[Index] = NewLines[Index] then
      Continue;
    if not EventLine(OldLines[Index], OldName, OldValue) or not EventLine(NewLines[Index], NewName, NewValue) or
      (OldName <> NewName) or (Length(Stack) = 0) or ((Length(Stack) > 1) and (Stack[High(Stack)] = '')) then
    begin
      AReason := Format('Zeile %d: %s', [Index + 1, Trimmed]);
      Exit(False);
    end;
    Change.Component := '';
    // Die oberste Ebene ist das Formular selbst.
    if Length(Stack) > 1 then
      Change.Component := Stack[High(Stack)];
    Change.EventName := OldName;
    Change.OldHandler := OldValue;
    Change.NewHandler := NewValue;
    AChanges := AChanges + [Change];
  end;
  Result := True;
end;

end.
