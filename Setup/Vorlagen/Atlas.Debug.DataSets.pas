unit Atlas.Debug.DataSets;

// Hilfsfunktionen für die Tabelle einer Datenmenge beim Debuggen mit Atlas
// (#3024, Knopf „Table“ im Fenster „Atlas: Auswerten“). Freiwillig: Ohne
// diese Unit liest Atlas die Datensätze über einzelne Auswertungen (langsamer,
// und nur mit Zustimmung, weil dafür der Cursor wandern muss).
//
// Einbinden: Unit ins Projekt kopieren (oder ihren Ordner in den Suchpfad
// aufnehmen) und, am besten nur in Debug-Builds, in irgendein uses schreiben:
//
//   uses
//     {$IFDEF DEBUG} Atlas.Debug.DataSets, {$ENDIF}
//     ...
//
// Atlas ruft im angehaltenen Programm AtlasDataSetRows auf und bekommt eine
// ganze Seite in einer Antwort. Dabei merkt sich die Funktion den aktuellen
// Datensatz (Bookmark), hängt BeforeScroll/AfterScroll und die gebundenen
// Steuerelemente ab und stellt am Ende alles wieder her. OnCalcFields und
// OnGetText laufen, weil die angezeigten Werte sie brauchen.
// Nur System und Data.DB, übersetzt mit Delphi 12 und neuer.

interface

uses
  Data.DB;

/// <summary>Bis zu ACount Datensätze ab Nummer AFirst (ab 1) als Text, höchstens etwa AMaxChars Zeichen. Erste
/// Zeile: Anzahl; dann je Datensatz Nummer und Felder (DisplayText), getrennt durch #9, Zeilen durch #10. In den
/// Werten stehen \t, \r, \n und \\ für Tabulator, Zeilenwechsel und \; \N heißt NULL. Datenmengen im Bearbeiten,
/// unidirektionale und geschlossene liefern „0“.</summary>
function AtlasDataSetRows(ADataSet: TDataSet; AFirst, ACount, AMaxChars: Integer): string;

/// <summary>Feld AField (ab 0) des Datensatzes ARecNo (ab 1) auf AValue setzen (Edit, AsString, Post). Ergebnis ''
/// bei Erfolg, sonst der Grund. Der aktuelle Datensatz bleibt derselbe.</summary>
function AtlasDataSetSetValue(ADataSet: TDataSet; ARecNo, AField: Integer; const AValue: string): string;

implementation

uses
  System.SysUtils;

const
  cNullMark = '\N';

type
  /// <summary>Zustand, der beim Lesen gesichert und danach wiederhergestellt wird.</summary>
  TSavedPlace = record
    Bookmark: TBookmark;
    BeforeScroll: TDataSetNotifyEvent;
    AfterScroll: TDataSetNotifyEvent;
  end;

var
  // Hält beide Funktionen im Programm: Der Linker entfernt sonst, was das Programm selbst nicht aufruft, und der
  // Debugger fände sie nicht.
  GKeep: array[0..1] of Pointer;

function Readable(ADataSet: TDataSet): Boolean;
begin
  Result := (ADataSet <> nil) and ADataSet.Active and (ADataSet.State = dsBrowse) and not ADataSet.IsUniDirectional;
end;

function Leave(ADataSet: TDataSet): TSavedPlace;
begin
  ADataSet.DisableControls;
  Result.Bookmark := ADataSet.Bookmark;
  Result.BeforeScroll := ADataSet.BeforeScroll;
  Result.AfterScroll := ADataSet.AfterScroll;
  ADataSet.BeforeScroll := nil;
  ADataSet.AfterScroll := nil;
end;

procedure Return(ADataSet: TDataSet; const APlace: TSavedPlace);
begin
  try
    if (Length(APlace.Bookmark) > 0) and ADataSet.BookmarkValid(APlace.Bookmark) then
    begin
      ADataSet.Bookmark := APlace.Bookmark;
    end;
  finally
    ADataSet.BeforeScroll := APlace.BeforeScroll;
    ADataSet.AfterScroll := APlace.AfterScroll;
    ADataSet.EnableControls;
  end;
end;

/// <summary>Cursor auf Datensatz ARecNo (ab 1); False, wenn es ihn nicht gibt.</summary>
function GoToRecord(ADataSet: TDataSet; ARecNo: Integer): Boolean;
begin
  ADataSet.First;
  Result := (ARecNo >= 1) and not ADataSet.Eof and (ADataSet.MoveBy(ARecNo - 1) = ARecNo - 1) and
    not ADataSet.Eof;
end;

function Escaped(const AText: string; AMaxLength: Integer): string;
var
  mChar: Char;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mChar in AText do
    begin
      if mBuilder.Length >= AMaxLength then
      begin
        mBuilder.Append('…');
        Break;
      end;
      case mChar of
        #9:
          mBuilder.Append('\t');
        #10:
          mBuilder.Append('\n');
        #13:
          mBuilder.Append('\r');
        '\':
          mBuilder.Append('\\');
      else
        mBuilder.Append(mChar);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function RowText(ADataSet: TDataSet; ARecNo, ACellLength: Integer): string;
var
  mIndex: Integer;
  mField: TField;
begin
  Result := IntToStr(ARecNo);
  for mIndex := 0 to ADataSet.FieldCount - 1 do
  begin
    mField := ADataSet.Fields[mIndex];
    if mField.IsNull then
    begin
      Result := Result + #9 + cNullMark;
    end
    else
    begin
      Result := Result + #9 + Escaped(mField.DisplayText, ACellLength);
    end;
  end;
end;

function AtlasDataSetRows(ADataSet: TDataSet; AFirst, ACount, AMaxChars: Integer): string;
var
  mPlace: TSavedPlace;
  mLines: string;
  mLine: string;
  mCount, mCellLength: Integer;
begin
  Result := '0';
  if not Readable(ADataSet) or (ACount <= 0) or (ADataSet.FieldCount = 0) then
  begin
    Exit;
  end;
  // Jeder Datensatz passt mindestens einmal in die Antwort.
  mCellLength := AMaxChars div (ADataSet.FieldCount + 1);
  if mCellLength < 8 then
  begin
    mCellLength := 8;
  end;
  mLines := '';
  mCount := 0;
  mPlace := Leave(ADataSet);
  try
    if GoToRecord(ADataSet, AFirst) then
    begin
      while not ADataSet.Eof and (mCount < ACount) do
      begin
        mLine := RowText(ADataSet, AFirst + mCount, mCellLength);
        if (mCount > 0) and (Length(mLines) + Length(mLine) + 1 > AMaxChars) then
        begin
          Break;
        end;
        mLines := mLines + #10 + mLine;
        Inc(mCount);
        ADataSet.Next;
      end;
    end;
  finally
    Return(ADataSet, mPlace);
  end;
  Result := IntToStr(mCount) + mLines;
end;

function AtlasDataSetSetValue(ADataSet: TDataSet; ARecNo, AField: Integer; const AValue: string): string;
var
  mPlace: TSavedPlace;
begin
  if not Readable(ADataSet) or (AField < 0) or (AField >= ADataSet.FieldCount) then
  begin
    Exit('The data set cannot be changed now.');
  end;
  Result := '';
  mPlace := Leave(ADataSet);
  try
    try
      if not GoToRecord(ADataSet, ARecNo) then
      begin
        Exit('Record not found.');
      end;
      ADataSet.Edit;
      ADataSet.Fields[AField].AsString := AValue;
      ADataSet.Post;
    except
      on E: Exception do
      begin
        if ADataSet.State in dsEditModes then
        begin
          ADataSet.Cancel;
        end;
        Result := E.Message;
      end;
    end;
  finally
    Return(ADataSet, mPlace);
  end;
end;

initialization
  GKeep[0] := @AtlasDataSetRows;
  GKeep[1] := @AtlasDataSetSetValue;

end.
