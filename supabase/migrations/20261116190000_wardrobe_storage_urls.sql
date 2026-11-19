-- Store the public Storage URL, not a handset-local path.
alter table public.wardrobe_items
  add column if not exists image_url text not null default '';

comment on column public.wardrobe_items.image_url is
  'Complete public URL for the cutout object in storage.buckets=cutouts.';

-- The client deliberately uses getPublicUrl(), so the bucket must be public.
-- RLS policies still restrict uploads, updates and deletes to the owner folder.
update storage.buckets
set public = true
where id = 'cutouts';

drop policy if exists "cutouts are readable by their owner" on storage.objects;
drop policy if exists "cutouts are writable by their owner" on storage.objects;
drop policy if exists "cutouts are updatable by their owner" on storage.objects;
drop policy if exists "cutouts are deletable by their owner" on storage.objects;

create policy "cutouts are readable by their owner"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'cutouts' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "cutouts are writable by their owner"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'cutouts' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "cutouts are updatable by their owner"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'cutouts' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "cutouts are deletable by their owner"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'cutouts' and (storage.foldername(name))[1] = auth.uid()::text);
