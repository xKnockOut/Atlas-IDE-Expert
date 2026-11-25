unit Atlas.Core.Commands.CustomKeys;

// Frei zugewiesene Tastenkürzel für Befehle der Befehlspalette (#2938), Teil
// ohne VCL und Open Tools API. Die Einstellung keys.commands (Registry
// CommandKeys) hält je Befehl „Befehlskennung=Taste“, durch „;“ getrennt, die
// Taste als TShortCut-Zahl wie die übrigen Tasten (#494), etwa
// „Atlas.FindMethod=16452“. Befehle mit eigener Einstellung keys.* stehen hier
// nicht. Beim Lesen fallen leere Kennungen, Taste 0 und unlesbare Einträge
// weg; eine Kennung gilt einmal (die letzte, Groß-/Kleinschreibung egal).
// Format schreibt in der Reihenfolge der Liste.
// Capture entscheidet im Zuweisungsdialog, welcher Tastendruck als Taste gilt:
// Umschalttasten allein nie, Buchstaben, Ziffern und Zeichen nur mit Strg oder
// Alt (sonst ginge das Tippen im Editor verloren), F1–F24 auch allein.

interface

type
  /// <summary>Taste eines Befehls der Befehlspalette (#2938).</summary>
  TAtlasCommandKey = record
    CommandId: string;
    /// <summary>TShortCut; 0 = keine Taste.</summary>
    Key: Word;
    class function Create(const ACommandId: string; AKey: Word): TAtlasCommandKey; static;
  end;

  /// <summary>Lesen, Schreiben und Ändern der Liste keys.commands.</summary>
  TAtlasCommandKeys = record
  public const
    cPairSeparator = ';';
    cValueSeparator = '=';
    cScShift = $2000;
    cScCtrl = $4000;
    cScAlt = $8000;
  public
    /// <summary>Taste aus virtuellem Tastencode und Umschaltung (cScShift, cScCtrl, cScAlt) als TShortCut; False
    /// für Umschalttasten allein und für Tasten ohne Strg/Alt außer F1–F24.</summary>
    class function Capture(AVirtualKey, AModifiers: Word; out AKey: Word): Boolean; static;
    /// <summary>Liste aus dem Text der Einstellung; Unlesbares fällt weg.</summary>
    class function Parse(const AText: string): TArray<TAtlasCommandKey>; static;
    /// <summary>Text der Einstellung; Einträge mit Taste 0 fallen weg.</summary>
    class function Format(const AKeys: TArray<TAtlasCommandKey>): string; static;
    /// <summary>Taste des Befehls ACommandId; 0 ohne.</summary>
    class function KeyOf(const AKeys: TArray<TAtlasCommandKey>; const ACommandId: string): Word; static;
    /// <summary>AKeys mit der Taste AKey für ACommandId (ersetzt eine vorhandene, AKey = 0 entfernt sie).
    /// </summary>
    class function WithKey(const AKeys: TArray<TAtlasCommandKey>; const ACommandId: string;
      AKey: Word): TArray<TAtlasCommandKey>; static;
    /// <summary>Text der Einstellung mit der Taste AKey für ACommandId (Parse, WithKey, Format).</summary>
    class function Assign(const AText, ACommandId: string; AKey: Word): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasCommandKey }

class function TAtlasCommandKey.Create(const ACommandId: string; AKey: Word): TAtlasCommandKey;
begin
  Result.CommandId := ACommandId;
  Result.Key := AKey;
end;

{ TAtlasCommandKeys }

class function TAtlasCommandKeys.Parse(const AText: string): TArray<TAtlasCommandKey>;
var
  mPair: string;
  mSeparator: Integer;
  mId: string;
  mValue: Integer;
begin
  Result := nil;
  for mPair in AText.Split([cPairSeparator]) do
  begin
    mSeparator := mPair.LastIndexOf(cValueSeparator);
    if mSeparator <= 0 then
    begin
      Continue;
    end;
    mId := mPair.Substring(0, mSeparator).Trim;
    if (mId = '') or not TryStrToInt(mPair.Substring(mSeparator + 1).Trim, mValue) or (mValue <= 0) or
      (mValue > High(Word)) then
    begin
      Continue;
    end;
    Result := WithKey(Result, mId, Word(mValue));
  end;
end;

class function TAtlasCommandKeys.Format(const AKeys: TArray<TAtlasCommandKey>): string;
var
  mKey: TAtlasCommandKey;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mKey in AKeys do
    begin
      if (mKey.Key = 0) or (mKey.CommandId.Trim = '') then
      begin
        Continue;
      end;
      if mBuilder.Length > 0 then
      begin
        mBuilder.Append(cPairSeparator);
      end;
      mBuilder.Append(mKey.CommandId.Trim).Append(cValueSeparator).Append(IntToStr(mKey.Key));
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasCommandKeys.KeyOf(const AKeys: TArray<TAtlasCommandKey>; const ACommandId: string): Word;
var
  mKey: TAtlasCommandKey;
begin
  Result := 0;
  for mKey in AKeys do
  begin
    if SameText(mKey.CommandId, ACommandId) then
    begin
      Exit(mKey.Key);
    end;
  end;
end;

class function TAtlasCommandKeys.WithKey(const AKeys: TArray<TAtlasCommandKey>; const ACommandId: string;
  AKey: Word): TArray<TAtlasCommandKey>;
var
  mKey: TAtlasCommandKey;
  mReplaced: Boolean;
begin
  Result := nil;
  mReplaced := False;
  for mKey in AKeys do
  begin
    if not SameText(mKey.CommandId, ACommandId) then
    begin
      Result := Result + [mKey];
    end
    else if not mReplaced and (AKey <> 0) then
    begin
      Result := Result + [TAtlasCommandKey.Create(mKey.CommandId, AKey)];
      mReplaced := True;
    end;
  end;
  if not mReplaced and (AKey <> 0) and (ACommandId.Trim <> '') then
  begin
    Result := Result + [TAtlasCommandKey.Create(ACommandId.Trim, AKey)];
  end;
end;

class function TAtlasCommandKeys.Capture(AVirtualKey, AModifiers: Word; out AKey: Word): Boolean;
const
  cVkShift = $10;
  cVkControl = $11;
  cVkMenu = $12;
  cVkCapital = $14;
  cVkLWin = $5B;
  cVkRWin = $5C;
  cVkF1 = $70;
  cVkF24 = $87;
  cVkLShift = $A0;
  cVkRMenu = $A5;
  cVkMaxKey = $FE;
var
  mModifiers: Word;
begin
  AKey := 0;
  mModifiers := AModifiers and (cScShift or cScCtrl or cScAlt);
  if (AVirtualKey = 0) or (AVirtualKey > cVkMaxKey) then
  begin
    Exit(False);
  end;
  // Umschalttasten allein (auch links/rechts getrennt und Feststelltaste) sind keine Taste.
  if (Byte(AVirtualKey) in [cVkShift, cVkControl, cVkMenu, cVkCapital, cVkLWin, cVkRWin]) or
    ((AVirtualKey >= cVkLShift) and (AVirtualKey <= cVkRMenu)) then
  begin
    Exit(False);
  end;
  if ((AVirtualKey < cVkF1) or (AVirtualKey > cVkF24)) and (mModifiers and (cScCtrl or cScAlt) = 0) then
  begin
    Exit(False);
  end;
  AKey := AVirtualKey or mModifiers;
  Result := True;
end;

class function TAtlasCommandKeys.Assign(const AText, ACommandId: string; AKey: Word): string;
begin
  Result := Format(WithKey(Parse(AText), ACommandId, AKey));
end;

end.
