require 'spec_helper'

require 'puppet/indirector/node/ldap'

describe Puppet::Node::Ldap do
  let(:nodename) { "mynode.domain.com" }
  let(:node_indirection) { Puppet::Node::Ldap.new }
  let(:environment) { Puppet::Node::Environment.create(:myenv, []) }
  let(:fact_values) { {:afact => "a value", "one" => "boo"} }
  let(:facts) { Puppet::Node::Facts.new(nodename, fact_values) }

  before do
    allow(Puppet::Node::Facts.indirection).to receive(:find).with(nodename, :environment => environment).and_return(facts)
  end

  describe "when searching for a single node" do
    let(:request) { Puppet::Indirector::Request.new(:node, :find, nodename, nil, :environment => environment) }

    it "should convert the hostname into a search filter" do
      allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({})
      entry = double('entry', :dn => 'cn=mynode.domain.com,ou=hosts,dc=madstop,dc=com', :vals => %w{})
      expect(node_indirection).to receive(:ldapsearch).with("(&(objectclass=puppetClient)(cn=#{nodename}))").and_yield(entry)
      node_indirection.name2hash(nodename)
    end

    it "should convert any found entry into a hash" do
      allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({})
      entry = double('entry', :dn => 'cn=mynode.domain.com,ou=hosts,dc=madstop,dc=com', :vals => %w{})
      expect(node_indirection).to receive(:ldapsearch).with("(&(objectclass=puppetClient)(cn=#{nodename}))").and_yield(entry)
      myhash = {"myhash" => true}
      expect(node_indirection).to receive(:entry2hash).with(entry).and_return(myhash)
      expect(node_indirection.name2hash(nodename)).to eq(myhash)
    end

    # This heavily tests our entry2hash method, so we don't have to stub out the stupid entry information any more.
    describe "when an ldap entry is found" do
      before do
        @entry = double('entry', :dn => 'cn=mynode,ou=hosts,dc=madstop,dc=com', :vals => %w{})
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({})
        allow(node_indirection).to receive(:ldapsearch).and_yield(@entry)
      end

      it "should convert the entry to a hash" do
        expect(node_indirection.entry2hash(@entry)).to be_instance_of(Hash)
      end

      it "should add the entry's common name to the hash if fqdn if false" do
        expect(node_indirection.entry2hash(@entry, false)[:name]).to eq("mynode")
      end

      it "should add the entry's fqdn name to the hash if fqdn if true" do
        expect(node_indirection.entry2hash(@entry, true)[:name]).to eq("mynode.madstop.com")
      end

      it "should add all of the entry's classes to the hash" do
        allow(@entry).to receive(:vals).with("puppetclass").and_return(%w{one two})
        expect(node_indirection.entry2hash(@entry)[:classes]).to eq(%w{one two})
      end

      it "should deduplicate class values" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({})
        allow(node_indirection).to receive(:class_attributes).and_return(%w{one two})
        allow(@entry).to receive(:vals).with("one").and_return(%w{a b})
        allow(@entry).to receive(:vals).with("two").and_return(%w{b c})
        expect(node_indirection.entry2hash(@entry)[:classes]).to eq(%w{a b c})
      end

      it "should add the entry's environment to the hash" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return(:environment => %w{production})
        expect(node_indirection.entry2hash(@entry)[:environment]).to eq("production")
      end

      it "should add all stacked parameters as parameters in the hash" do
        allow(@entry).to receive(:vals).with("puppetvar").and_return(%w{one=two three=four})
        result = node_indirection.entry2hash(@entry)
        expect(result[:parameters]["one"]).to eq("two")
        expect(result[:parameters]["three"]).to eq("four")
      end

      it "should not add the stacked parameter as a normal parameter" do
        allow(@entry).to receive(:vals).with("puppetvar").and_return(%w{one=two three=four})
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return("puppetvar" => %w{one=two three=four})
        expect(node_indirection.entry2hash(@entry)[:parameters]["puppetvar"]).to be_nil
      end

      it "should add all other attributes as parameters in the hash" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return("foo" => %w{one two})
        expect(node_indirection.entry2hash(@entry)[:parameters]["foo"]).to eq(%w{one two})
      end

      it "should return single-value parameters as strings, not arrays" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return("foo" => %w{one})
        expect(node_indirection.entry2hash(@entry)[:parameters]["foo"]).to eq("one")
      end

      it "should convert 'true' values to the boolean 'true'" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({"one" => ["true"]})
        expect(node_indirection.entry2hash(@entry)[:parameters]["one"]).to eq(true)
      end

      it "should convert 'false' values to the boolean 'false'" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({"one" => ["false"]})
        expect(node_indirection.entry2hash(@entry)[:parameters]["one"]).to eq(false)
      end

      it "should convert 'true' values to the boolean 'true' inside an array" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({"one" => ["true", "other"]})
        expect(node_indirection.entry2hash(@entry)[:parameters]["one"]).to eq([true, "other"])
      end

      it "should convert 'false' values to the boolean 'false' inside an array" do
        allow(node_indirection).to receive(:ldap_entry_to_hash).and_return({"one" => ["false", "other"]})
        expect(node_indirection.entry2hash(@entry)[:parameters]["one"]).to eq([false, "other"])
      end

      it "should add the parent's name if present" do
        allow(@entry).to receive(:vals).with("parentnode").and_return(%w{foo})
        expect(node_indirection.entry2hash(@entry)[:parent]).to eq("foo")
      end

      it "should fail if more than one parent is specified" do
        allow(@entry).to receive(:vals).with("parentnode").and_return(%w{foo})
        expect(node_indirection.entry2hash(@entry)[:parent]).to eq("foo")
      end
    end

    it "should search first for the provided key" do
      expect(node_indirection).to receive(:name2hash).with("mynode.domain.com").and_return({})
      node_indirection.find(request)
    end

    it "should search for the short version of the provided key if the key looks like a hostname and no results are found for the key itself" do
      expect(node_indirection).to receive(:name2hash).with("mynode.domain.com").and_return(nil)
      expect(node_indirection).to receive(:name2hash).with("mynode").and_return({})
      node_indirection.find(request)
    end

    it "should search for default information if no information can be found for the key" do
      expect(node_indirection).to receive(:name2hash).with("mynode.domain.com").and_return(nil)
      expect(node_indirection).to receive(:name2hash).with("mynode").and_return(nil)
      expect(node_indirection).to receive(:name2hash).with("default").and_return({})
      node_indirection.find(request)
    end

    it "should return nil if no results are found in ldap" do
      allow(node_indirection).to receive(:name2hash).and_return(nil)
      expect(node_indirection.find(request)).to be_nil
    end

    it "should return a node object if results are found in ldap" do
      allow(node_indirection).to receive(:name2hash).and_return({})
      expect(node_indirection.find(request)).to be
    end

    describe "and node information is found in LDAP" do
      before do
        @result = {}
        allow(node_indirection).to receive(:name2hash).and_return(@result)
      end

      it "should create the node with the correct name, even if it was found by a different name" do
        expect(node_indirection).to receive(:name2hash).with(nodename).and_return(nil)
        expect(node_indirection).to receive(:name2hash).with("mynode").and_return(@result)

        expect(node_indirection.find(request).name).to eq(nodename)
      end

      it "should add any classes from ldap" do
        classes = %w{a b c d}
        @result[:classes] = classes
        expect(node_indirection.find(request).classes).to eq(classes)
      end

      it "should add all entry attributes as node parameters" do
        params = {"one" => "two", "three" => "four"}
        @result[:parameters] = params
        expect(node_indirection.find(request).parameters).to include(params)
      end

      it "should set the node's environment to the environment of the results" do
        result_env = Puppet::Node::Environment.create(:local_test, [])
        allow(Puppet::Node::Facts.indirection).to receive(:find).with(nodename, :environment => result_env).and_return(facts)
        @result[:environment] = "local_test"

        Puppet.override(:environments => Puppet::Environments::Static.new(result_env)) do
          expect(node_indirection.find(request).environment).to eq(result_env)
        end
      end

      it "should retain false parameter values" do
        @result[:parameters] = {}
        @result[:parameters]["one"] = false
        expect(node_indirection.find(request).parameters).to include({"one" => false})
      end

      context("when merging facts") do
        let(:request_facts) { Puppet::Node::Facts.new('test', 'foo' => 'bar') }
        let(:indirection_facts) { Puppet::Node::Facts.new('test', 'baz' => 'qux') }

        it "should merge facts from the request if supplied" do
          request.options[:facts] = request_facts
          allow(Puppet::Node::Facts).to receive(:find).and_return(indirection_facts)

          expect(node_indirection.find(request).parameters).to include(request_facts.values)
          expect(node_indirection.find(request).facts).to eq(request_facts)
        end

        it "should find facts if none are supplied" do
          allow(Puppet::Node::Facts.indirection).to receive(:find).with(nodename, :environment => environment).and_return(indirection_facts)
          request.options.delete(:facts)

          expect(node_indirection.find(request).parameters).to include(indirection_facts.values)
          expect(node_indirection.find(request).facts).to eq(indirection_facts)
        end

        it "should merge the node's facts after the parameters from ldap are assigned" do
          # Make sure we've got data to start with, so the parameters are actually set.
          params = {"one" => "yay", "two" => "hooray"}
          @result[:parameters] = params

          # Node implements its own merge so that an existing param takes
          # precedence over facts. We get the same result here by merging params
          # into facts
          expect(node_indirection.find(request).parameters).to eq(facts.values.merge(params))
        end
      end

      describe "and a parent node is specified" do
        before do
          @entry = {:classes => [], :parameters => {}}
          @parent = {:classes => [], :parameters => {}}
          @parent_parent = {:classes => [], :parameters => {}}

          allow(node_indirection).to receive(:name2hash).with(nodename).and_return(@entry)
          allow(node_indirection).to receive(:name2hash).with('parent').and_return(@parent)
          allow(node_indirection).to receive(:name2hash).with('parent_parent').and_return(@parent_parent)

          allow(node_indirection).to receive(:parent_attribute).and_return(:parent)
        end

        it "should search for the parent node" do
          @entry[:parent] = "parent"
          expect(node_indirection).to receive(:name2hash).with(nodename).and_return(@entry)
          expect(node_indirection).to receive(:name2hash).with('parent').and_return(@parent)

          node_indirection.find(request)
        end

        it "should fail if the parent cannot be found" do
          @entry[:parent] = "parent"

          expect(node_indirection).to receive(:name2hash).with('parent').and_return(nil)

          expect { node_indirection.find(request) }.to raise_error(Puppet::Error, /Could not find parent node/)
        end

        it "should add any parent classes to the node's classes" do
          @entry[:parent] = "parent"
          @entry[:classes] = %w{a b}

          @parent[:classes] = %w{c d}

          expect(node_indirection.find(request).classes).to eq(%w{a b c d})
        end

        it "should add any parent parameters to the node's parameters" do
          @entry[:parent] = "parent"
          @entry[:parameters]["one"] = "two"

          @parent[:parameters]["three"] = "four"

          expect(node_indirection.find(request).parameters).to include({"one" => "two", "three" => "four"})
        end

        it "should prefer node parameters over parent parameters" do
          @entry[:parent] = "parent"
          @entry[:parameters]["one"] = "two"

          @parent[:parameters]["one"] = "three"

          expect(node_indirection.find(request).parameters).to include({"one" => "two"})
        end

        it "should use the parent's environment if the node has none" do
          env = Puppet::Node::Environment.create(:parent, [])
          @entry[:parent] = "parent"

          @parent[:environment] = "parent"

          allow(Puppet::Node::Facts.indirection).to receive(:find).with(nodename, :environment => env).and_return(facts)

          Puppet.override(:environments => Puppet::Environments::Static.new(env)) do
            expect(node_indirection.find(request).environment).to eq(env)
          end
        end

        it "should prefer the node's environment to the parent's" do
          child_env = Puppet::Node::Environment.create(:child, [])
          @entry[:parent] = "parent"
          @entry[:environment] = "child"

          @parent[:environment] = "parent"

          allow(Puppet::Node::Facts.indirection).to receive(:find).with(nodename, :environment => child_env).and_return(facts)

          Puppet.override(:environments => Puppet::Environments::Static.new(child_env)) do

            expect(node_indirection.find(request).environment).to eq(child_env)
          end
        end

        it "should recursively look up parent information" do
          @entry[:parent] = "parent"
          @entry[:parameters]["one"] = "two"

          @parent[:parent] = "parent_parent"
          @parent[:parameters]["three"] = "four"

          @parent_parent[:parameters]["five"] = "six"

          expect(node_indirection.find(request).parameters).to include("one" => "two", "three" => "four", "five" => "six")
        end

        it "should not allow loops in parent declarations" do
          @entry[:parent] = "parent"
          @parent[:parent] = nodename
          expect { node_indirection.find(request) }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe "when searching for multiple nodes" do
    let(:options) { {:environment => environment} }
    let(:request) { Puppet::Indirector::Request.new(:node, :find, nodename, nil, options) }

    before :each do
      allow(Puppet::Node::Facts.indirection).to receive(:terminus_class).and_return(:yaml)
    end

    it "should find all nodes if no arguments are provided" do
      expect(node_indirection).to receive(:ldapsearch).with("(objectclass=puppetClient)")
      # LAK:NOTE The search method requires an essentially bogus key.  It's
      # an API problem that I don't really know how to fix.
      node_indirection.search request
    end

    describe "and a class is specified" do
      it "should find all nodes that are members of that class" do
        expect(node_indirection).to receive(:ldapsearch).with("(&(objectclass=puppetClient)(puppetclass=one))")

        options[:class] = "one"
        node_indirection.search request
      end
    end

    describe "multiple classes are specified" do
      it "should find all nodes that are members of all classes" do
        expect(node_indirection).to receive(:ldapsearch).with("(&(objectclass=puppetClient)(puppetclass=one)(puppetclass=two))")
        options[:class] = %w{one two}
        node_indirection.search request
      end
    end

    it "should process each found entry" do
      expect(node_indirection).to receive(:ldapsearch).and_yield("one")
      expect(node_indirection).to receive(:entry2hash).with("one",nil).and_return(:name => nodename)
      node_indirection.search request
    end

    it "should return a node for each processed entry with the name from the entry" do
      expect(node_indirection).to receive(:ldapsearch).and_yield("whatever")
      expect(node_indirection).to receive(:entry2hash).with("whatever",nil).and_return(:name => nodename)
      result = node_indirection.search(request)
      expect(result[0]).to be_instance_of(Puppet::Node)
      expect(result[0].name).to eq(nodename)
    end

    it "should merge each node's facts" do
      allow(node_indirection).to receive(:ldapsearch).and_yield("one")
      allow(node_indirection).to receive(:entry2hash).with("one",nil).and_return(:name => nodename)
      expect(node_indirection.search(request)[0].parameters).to include(fact_values)
    end

    it "should pass the request's fqdn option to entry2hash" do
      options[:fqdn] = :hello
      allow(node_indirection).to receive(:ldapsearch).and_yield("one")
      expect(node_indirection).to receive(:entry2hash).with("one",:hello).and_return(:name => nodename)
      node_indirection.search(request)
    end
  end

  describe Puppet::Node::Ldap, " when developing the search query" do
    it "should return the value of the :ldapclassattrs split on commas as the class attributes" do
      Puppet[:ldapclassattrs] = "one,two"
      expect(node_indirection.class_attributes).to eq(%w{one two})
    end

    it "should return nil as the parent attribute if the :ldapparentattr is set to an empty string" do
      Puppet[:ldapparentattr] = ""
      expect(node_indirection.parent_attribute).to be_nil
    end

    it "should return the value of the :ldapparentattr as the parent attribute" do
      Puppet[:ldapparentattr] = "pere"
      expect(node_indirection.parent_attribute).to eq("pere")
    end

    it "should use the value of the :ldapstring as the search filter" do
      Puppet[:ldapstring] = "mystring"
      expect(node_indirection.search_filter("testing")).to eq("mystring")
    end

    it "should replace '%s' with the node name in the search filter if it is present" do
      Puppet[:ldapstring] = "my%sstring"
      expect(node_indirection.search_filter("testing")).to eq("mytestingstring")
    end

    it "should not modify the global :ldapstring when replacing '%s' in the search filter" do
      filter = double('filter')
      expect(filter).to receive(:include?).with("%s").and_return(true)
      expect(filter).to receive(:gsub).with("%s", "testing").and_return("mynewstring")
      Puppet[:ldapstring] = filter
      expect(node_indirection.search_filter("testing")).to eq("mynewstring")
    end
  end

  describe Puppet::Node::Ldap, " when deciding attributes to search for" do
    it "should use 'nil' if the :ldapattrs setting is 'all'" do
      Puppet[:ldapattrs] = "all"
      expect(node_indirection.search_attributes).to be_nil
    end

    it "should split the value of :ldapattrs on commas and use the result as the attribute list" do
      Puppet[:ldapattrs] = "one,two"
      allow(node_indirection).to receive(:class_attributes).and_return([])
      allow(node_indirection).to receive(:parent_attribute).and_return(nil)
      expect(node_indirection.search_attributes).to eq(%w{one two})
    end

    it "should add the class attributes to the search attributes if not returning all attributes" do
      Puppet[:ldapattrs] = "one,two"
      allow(node_indirection).to receive(:class_attributes).and_return(%w{three four})
      allow(node_indirection).to receive(:parent_attribute).and_return(nil)
      # Sort them so i don't have to care about return order
      expect(node_indirection.search_attributes.sort).to eq(%w{one two three four}.sort)
    end

    it "should add the parent attribute to the search attributes if not returning all attributes" do
      Puppet[:ldapattrs] = "one,two"
      allow(node_indirection).to receive(:class_attributes).and_return([])
      allow(node_indirection).to receive(:parent_attribute).and_return("parent")
      expect(node_indirection.search_attributes.sort).to eq(%w{one two parent}.sort)
    end

    it "should not add nil parent attributes to the search attributes" do
      Puppet[:ldapattrs] = "one,two"
      allow(node_indirection).to receive(:class_attributes).and_return([])
      allow(node_indirection).to receive(:parent_attribute).and_return(nil)
      expect(node_indirection.search_attributes).to eq(%w{one two})
    end
  end
end
