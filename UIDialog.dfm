object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Anycubic PHOTON file processor'
  ClientHeight = 947
  ClientWidth = 1053
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnResize = FormResize
  DesignSize = (
    1053
    947)
  PixelsPerInch = 96
  TextHeight = 13
  object layerOut: TImage
    Left = 8
    Top = 8
    Width = 615
    Height = 846
    Anchors = [akLeft, akTop, akRight, akBottom]
    Constraints.MaxHeight = 2560
    Constraints.MaxWidth = 1440
    Constraints.MinHeight = 400
    Constraints.MinWidth = 300
    ExplicitWidth = 601
    ExplicitHeight = 400
  end
  object lbInfo: TLabel
    Left = 638
    Top = 718
    Width = 24
    Height = 13
    Anchors = [akRight, akBottom]
    Caption = 'Info:'
    ExplicitLeft = 624
    ExplicitTop = 272
  end
  object btnOpenFile: TButton
    Left = 8
    Top = 914
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = '&Open File'
    TabOrder = 0
    OnClick = btnOpenFileClick
  end
  object vleGlobals: TValueListEditor
    Left = 629
    Top = 8
    Width = 416
    Height = 703
    Anchors = [akTop, akRight, akBottom]
    Strings.Strings = (
      'Layer thickness (mm)=0.0'
      'Normal exposure time (s)=0'
      'Off time (s)=0'
      'Normal layers=0'
      'Bottom exposure time=0'
      'Bottom exp. decrement=0'
      'Bottom layers=0'
      'Bed dimension X=0'
      'Bed dimension Y=0'
      'Bed dimension Z=0'
      'X Resolution=1440'
      'Y Resolution=2560'
      'Interleave program=0c'
      'Coarse neighbors=7'
      'LUA script=pproc.lua')
    TabOrder = 1
    OnStringsChange = vleGlobalsStringsChange
    ColWidths = (
      268
      142)
  end
  object sbLayerSelect: TScrollBar
    Left = 8
    Top = 883
    Width = 1037
    Height = 16
    Anchors = [akLeft, akRight, akBottom]
    PageSize = 0
    TabOrder = 2
    OnScroll = sbLayerSelectScroll
  end
  object btnProcessLayers: TButton
    Left = 629
    Top = 765
    Width = 99
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = '&Process layers'
    Enabled = False
    TabOrder = 3
    OnClick = btnProcessLayersClick
  end
  object pbStatus: TProgressBar
    Left = 629
    Top = 743
    Width = 416
    Height = 16
    Anchors = [akRight, akBottom]
    TabOrder = 4
  end
  object btnSaveFile: TButton
    Left = 89
    Top = 914
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Save File'
    Enabled = False
    TabOrder = 5
    OnClick = btnSaveFileClick
  end
  object cbxAddLayers: TCheckBox
    Left = 750
    Top = 769
    Width = 97
    Height = 17
    Hint = 'Modified layers will be added with same height'
    Anchors = [akRight, akBottom]
    Caption = 'Add new Layers'
    TabOrder = 6
  end
  object cbxShowPreview0: TCheckBox
    Left = 8
    Top = 860
    Width = 97
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Show Preview &0'
    Checked = True
    State = cbChecked
    TabOrder = 7
    WordWrap = True
    OnClick = cbxShowPreview0Click
  end
  object cbxShowPreview1: TCheckBox
    Left = 120
    Top = 860
    Width = 97
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Show Preview &1'
    TabOrder = 8
    WordWrap = True
    OnClick = cbxShowPreview1Click
  end
  object btnSelectScript: TButton
    Left = 629
    Top = 796
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Select Script'
    TabOrder = 9
    OnClick = btnSelectScriptClick
  end
  object uiOpenDialog: TOpenDialog
    Filter = 'Anycubc PHOTON files|*.photon'
    Left = 48
    Top = 384
  end
  object uiSaveDialog: TSaveDialog
    Filter = 'Anycubc PHOTON files|*.photon'
    Left = 120
    Top = 384
  end
end
