ODS("Script~C0A 'pproc.lua'~C07 executed in thread~C0E "..thread_name.."~C07")

-- available globals:
--  def_layer_thickness  (float)
--  def_exposure_time    (float)
--  def_off_time         (float)
--  def_bottom_time      (float)
--  bottom_layers        (int)
--  def_coarse_neighbors (int)
--  program_code         (char)
--  photon_file          (object)
--  layer                (object)

function process_layer()
 if program_code == 'c' then
   layer:coarse()
   -- layer:coarse(def_coarse_neighbors, 0, 1280, 1438, 2558) -- lower half of layer, for testing
 else
   ODS(string.format("unsupported program code [%s]", program_code))    
 end   
end