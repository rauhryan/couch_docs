require 'rubygems'
require 'restclient'
require 'json'

module CouchDocs
  class Store
    include Enumerable

    attr_accessor :url, :design_docs_only

    # Initialize a CouchDB store object.  Requires a URL for the
    # target CouchDB database.
    #
    def initialize(url, options={})
      @url = url
      @design_docs_only = (options[:only] == :design)
    end

    # Loads all supplied design documents in the current store.
    # Given a hash <tt>h</tt>, the keys being the CouchDB document
    # name and values of design documents
    #
    def put_design_documents(h)
      h.each_pair do |document_name, doc|
        Store.put!("#{url}/_design/#{document_name}", doc)
      end
    end

    # Create or replace the document located at <tt>path</tt> with the
    # Hash document <tt>doc</tt>
    #
    def self.put!(path, doc)
      self.put(path, doc)
    rescue RestClient::RequestFailed
      self.delete_and_put(path, doc)
    end

    def self.delete_and_put(path, doc)
      self.delete(path)
      self.put(path, doc)
    end

    def self.put(path, doc)
      RestClient.put path,
        doc.to_json,
        :content_type => 'application/json'
    end

    def self.post(path, doc)
      RestClient.post path,
        doc.to_json,
        :content_type => 'application/json'
    end

    def self.delete(path)
      # retrieve existing to obtain the revision
      old = self.get(path)
      url = old['_rev'] ? path + "?rev=#{old['_rev']}" : path
      RestClient.delete(url)
    end

    def self.get(path)
      JSON.parse(RestClient.get(path))
    end

    def each
      all_url = "#{url}/_all_docs" +
        (design_docs_only ? '?startkey=%22_design%22&endkey=%22_design0%22' : "")
      Store.get(all_url)['rows'].each do |rec|
        yield Store.get("#{url}/#{rec['id']}?attachments=true")
      end
    end
  end
end
