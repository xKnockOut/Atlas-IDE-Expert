unit Atlas.Core.Editor.FormatLog;

// Protokollzeilen des Befehls „Formatieren“ (#43), ohne Open Tools API: Welche
// Markierung die IDE gemeldet hat, ob die ganze Datei oder nur ein Bereich an
// den Server ging und welche Zeilen die Antwort ändert. Damit lässt sich im
// Protokoll prüfen, ob trotz Markierung die ganze Unit formatiert wurde.
// Anonym: nur Zahlen, weder Dateiname noch Quelltext. Zeilen 1-basiert wie im
// Editor; ein Bereich, der am Anfang einer Zeile endet, schließt diese Zeile
// nicht ein (wie beim Server, Atlas.Common.Lsp.Formatting).

interface

uses
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  /// <summary>Texte fürs Protokoll beim Formatieren; nur Zahlen.</summary>
  TAtlasFormatLog = class
  public
    /// <summary>Zeile vor der Anfrage: Zustand des Blocks der IDE und gesendeter Bereich (leer = ganze
    /// Datei).</summary>
    class function Request(ABlockValid: Boolean; ABlockSize: Integer; const ASelection: TLspRange): string;
      static;
    /// <summary>Zeile nach der Antwort: Zahl der Änderungen, betroffene Zeilen und wie viele davon außerhalb
    /// des Bereichs liegen.</summary>
    class function Answer(const AEdits: TArray<TLspTextEdit>; const ASelection: TLspRange): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  cPrefix = 'Format: ';

/// <summary>Erste und letzte Zeile (0-basiert) von AStart bis AEnd; ein Ende am Zeilenanfang zählt nicht
/// mit.</summary>
procedure LinesOf(const AStart, AEnd: TLspTextPosition; out AFirst, ALast: Integer);
begin
  AFirst := AStart.Line;
  ALast := AEnd.Line;
  if (AEnd.Character = 0) and (ALast > AFirst) then
  begin
    Dec(ALast);
  end;
end;

function LinesText(AFirst, ALast: Integer): string;
begin
  Result := Format('lines %d-%d', [AFirst + 1, ALast + 1]);
end;

function YesNo(AValue: Boolean): string;
begin
  Result := 'no';
  if AValue then
  begin
    Result := 'yes';
  end;
end;

class function TAtlasFormatLog.Request(ABlockValid: Boolean; ABlockSize: Integer;
  const ASelection: TLspRange): string;
var
  mFirst, mLast: Integer;
begin
  Result := cPrefix + Format('block valid=%s size=%d, ', [YesNo(ABlockValid), ABlockSize]);
  if ASelection.IsEmpty then
  begin
    Result := Result + 'no selection -> formatting (whole file)';
    Exit;
  end;
  LinesOf(ASelection.StartPos, ASelection.EndPos, mFirst, mLast);
  Result := Result + 'selection ' + LinesText(mFirst, mLast) + ' -> rangeFormatting';
end;

class function TAtlasFormatLog.Answer(const AEdits: TArray<TLspTextEdit>; const ASelection: TLspRange): string;
var
  mEdit: TLspTextEdit;
  mFirst, mLast, mSelFirst, mSelLast, mEditFirst, mEditLast, mOutside: Integer;
begin
  Result := cPrefix + Format('%d edits', [Length(AEdits)]);
  if Length(AEdits) = 0 then
  begin
    Exit;
  end;
  LinesOf(ASelection.StartPos, ASelection.EndPos, mSelFirst, mSelLast);
  mFirst := MaxInt;
  mLast := -1;
  mOutside := 0;
  for mEdit in AEdits do
  begin
    LinesOf(mEdit.StartPos, mEdit.EndPos, mEditFirst, mEditLast);
    mFirst := Min(mFirst, mEditFirst);
    mLast := Max(mLast, mEditLast);
    if (mEditFirst < mSelFirst) or (mEditLast > mSelLast) then
    begin
      Inc(mOutside);
    end;
  end;
  Result := Result + ', ' + LinesText(mFirst, mLast);
  if not ASelection.IsEmpty then
  begin
    Result := Result + Format(', %d outside selection', [mOutside]);
  end;
end;

end.
